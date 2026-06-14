package com.course.tasksapi.handlers;

import com.course.tasksapi.events.EventPublisher;
import com.course.tasksapi.model.Task;
import com.course.tasksapi.repo.TaskRepository;
import com.course.tasksapi.util.ApiException;
import com.course.tasksapi.util.Http;
import com.course.tasksapi.util.Json;
import com.course.tasksapi.util.Logging;
import com.fasterxml.jackson.databind.JsonNode;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Handles everything under {@code /tasks}:
 * <pre>
 *   GET    /tasks         list
 *   POST   /tasks         create
 *   GET    /tasks/{id}    fetch one
 *   PUT    /tasks/{id}    update (full or partial)
 *   DELETE /tasks/{id}    delete
 * </pre>
 *
 * <p><b>Routing gotcha.</b> HttpServer matches a context by PATH PREFIX, so the
 * single "/tasks" context also receives "/tasksfoo" and "/tasks/{id}/extra".
 * This handler therefore inspects the exact path itself and returns 404 for
 * anything that is not exactly the collection or a single {@code {id}} segment.
 * (A test pins this behaviour.)
 */
public class TasksHandler implements HttpHandler {

    private static final String COLLECTION = "/tasks";
    private static final String PREFIX = "/tasks/";

    private final TaskRepository repo;
    private final EventPublisher events;

    public TasksHandler(TaskRepository repo, EventPublisher events) {
        this.repo = repo;
        this.events = events;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        String path = exchange.getRequestURI().getPath();
        String method = exchange.getRequestMethod();

        if (path.equals(COLLECTION) || path.equals(PREFIX)) {
            // The collection: /tasks (or /tasks/)
            handleCollection(exchange, method);
            return;
        }
        if (path.startsWith(PREFIX)) {
            String rest = path.substring(PREFIX.length());
            // A valid item path has exactly one non-empty segment: /tasks/{id}.
            // Reject sub-resources (/tasks/{id}/x) and empty ids.
            if (rest.isEmpty() || rest.contains("/")) {
                throw ApiException.notFound("No route for " + method + " " + path);
            }
            handleItem(exchange, method, rest);
            return;
        }
        // e.g. "/tasksfoo" landed here only because of prefix matching.
        throw ApiException.notFound("No route for " + method + " " + path);
    }

    // --- collection: /tasks --------------------------------------------------

    private void handleCollection(HttpExchange exchange, String method) throws IOException {
        switch (method) {
            case "GET":
                listTasks(exchange);
                break;
            case "POST":
                createTask(exchange);
                break;
            default:
                throw methodNotAllowed(exchange, "GET, POST");
        }
    }

    private void listTasks(HttpExchange exchange) throws IOException {
        List<Task> tasks = repo.findAll();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("tasks", tasks);
        body.put("count", tasks.size());
        Http.writeJson(exchange, 200, body);
    }

    private void createTask(HttpExchange exchange) throws IOException {
        requireJson(exchange);
        JsonNode node = parseBody(exchange);

        String title = text(node, "title");
        String description = text(node, "description");
        validateTitle(title);
        validateDescription(description);

        // Server controls id, createdAt and done — client values are ignored.
        Task task = repo.save(Task.create(title.trim(), description));

        // Best-effort event publish: never fail the request because of it (FR-7).
        try {
            events.taskCreated(task);
        } catch (Exception e) {
            Logging.warn("Failed to publish TASK_CREATED for task " + task.getId(), e);
        }

        exchange.getResponseHeaders().set("Location", "/tasks/" + task.getId());
        Http.writeJson(exchange, 201, task);
    }

    // --- item: /tasks/{id} ---------------------------------------------------

    private void handleItem(HttpExchange exchange, String method, String id) throws IOException {
        switch (method) {
            case "GET":
                getTask(exchange, id);
                break;
            case "PUT":
                updateTask(exchange, id);
                break;
            case "DELETE":
                deleteTask(exchange, id);
                break;
            default:
                throw methodNotAllowed(exchange, "GET, PUT, DELETE");
        }
    }

    private void getTask(HttpExchange exchange, String id) throws IOException {
        Task task = repo.findById(id)
                .orElseThrow(() -> ApiException.notFound("Task not found: " + id));
        Http.writeJson(exchange, 200, task);
    }

    private void updateTask(HttpExchange exchange, String id) throws IOException {
        requireJson(exchange);
        JsonNode node = parseBody(exchange);

        Task task = repo.findById(id)
                .orElseThrow(() -> ApiException.notFound("Task not found: " + id));

        // Partial update: only the fields present in the body are changed. This
        // supports both {"done":true} and {"title","description","done"} (§8.1).
        if (node.has("title")) {
            String title = text(node, "title");
            validateTitle(title);
            task.setTitle(title.trim());
        }
        if (node.has("description")) {
            String description = text(node, "description");
            validateDescription(description);
            task.setDescription(description);
        }
        if (node.has("done")) {
            JsonNode done = node.get("done");
            if (!done.isBoolean()) {
                throw ApiException.validation("done must be a boolean");
            }
            task.setDone(done.asBoolean());
        }

        Http.writeJson(exchange, 200, repo.save(task));
    }

    private void deleteTask(HttpExchange exchange, String id) throws IOException {
        if (!repo.deleteById(id)) {
            throw ApiException.notFound("Task not found: " + id);
        }
        Http.writeNoContent(exchange);
    }

    // --- shared helpers ------------------------------------------------------

    /** Reject requests whose body is not declared as JSON (FR-1) → 415. */
    private static void requireJson(HttpExchange exchange) {
        String contentType = exchange.getRequestHeaders().getFirst("Content-Type");
        if (contentType == null || !contentType.toLowerCase().contains("application/json")) {
            throw ApiException.unsupportedMediaType("Content-Type must be application/json");
        }
    }

    private static JsonNode parseBody(HttpExchange exchange) throws IOException {
        String raw = Http.readBody(exchange);
        if (raw == null || raw.isBlank()) {
            throw ApiException.badRequest("Request body is required");
        }
        try {
            return Json.parse(raw);
        } catch (RuntimeException e) {
            throw ApiException.badRequest(e.getMessage());
        }
    }

    /** Read a string field from the JSON tree, or null if absent/null. */
    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return (value == null || value.isNull()) ? null : value.asText();
    }

    private static void validateTitle(String title) {
        if (title == null || title.trim().isEmpty()) {
            throw ApiException.validation("title is required and must not be blank");
        }
        if (title.length() > 200) {
            throw ApiException.validation("title must be at most 200 characters");
        }
    }

    private static void validateDescription(String description) {
        if (description != null && description.length() > 2000) {
            throw ApiException.validation("description must be at most 2000 characters");
        }
    }

    /** Set the {@code Allow} header and build a 405 error. */
    private static ApiException methodNotAllowed(HttpExchange exchange, String allowed) {
        exchange.getResponseHeaders().set("Allow", allowed);
        return ApiException.methodNotAllowed("Method not allowed; allowed methods: " + allowed);
    }
}
