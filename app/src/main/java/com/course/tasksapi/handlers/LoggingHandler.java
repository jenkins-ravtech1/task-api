package com.course.tasksapi.handlers;

import com.course.tasksapi.util.ApiException;
import com.course.tasksapi.util.Http;
import com.course.tasksapi.util.Logging;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;
import java.util.Map;
import java.util.UUID;

/**
 * A wrapper ("decorator") placed around every real handler. It owns the three
 * cross-cutting concerns so the business handlers don't have to:
 *
 * <ol>
 *   <li><b>Request id</b> (FR-5): generate a UUID and return it as the
 *       {@code X-Request-Id} response header.</li>
 *   <li><b>Error shape</b> (FR-3): catch {@link ApiException} (expected errors)
 *       and any other exception (unexpected → 500) and write the standard
 *       {@code {"error","message"}} body.</li>
 *   <li><b>Structured log</b> (FR-4): emit exactly one JSON line per request with
 *       method, path, status and duration.</li>
 * </ol>
 *
 * <p>This is the classic Decorator pattern: {@code LoggingHandler} implements the
 * same {@link HttpHandler} interface it wraps, so {@code App} can nest them
 * freely.
 */
public class LoggingHandler implements HttpHandler {

    private final HttpHandler delegate;

    public LoggingHandler(HttpHandler delegate) {
        this.delegate = delegate;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        long startNanos = System.nanoTime();
        String requestId = UUID.randomUUID().toString();

        // Make the id available to handlers and to the client. Headers must be
        // set BEFORE the body is sent, so we do it first thing.
        exchange.setAttribute("requestId", requestId);
        exchange.getResponseHeaders().set("X-Request-Id", requestId);

        String method = exchange.getRequestMethod();
        String path = exchange.getRequestURI().getPath();
        // Default to 500; overwritten below once we know the real outcome. A
        // default is required because the finally block always reads `status`.
        int status = 500;

        try {
            delegate.handle(exchange);
            // getResponseCode() returns the status the handler already sent,
            // or -1 if it somehow sent nothing.
            status = exchange.getResponseCode();
            if (status == -1) {
                status = 200;
            }
        } catch (ApiException e) {
            // Expected, "well-formed" errors (validation, not-found, ...).
            status = e.status();
            safeWriteError(exchange, e.status(), e.code(), e.getMessage());
        } catch (Exception e) {
            // Anything else is a bug or an unexpected failure → 500.
            status = 500;
            Logging.error("Unhandled error while processing request", e,
                    Map.of("requestId", requestId, "method", method, "path", path));
            safeWriteError(exchange, 500, "INTERNAL", "Internal server error");
        } finally {
            long durationMs = (System.nanoTime() - startNanos) / 1_000_000;
            Logging.request(requestId, method, path, status, durationMs);
            exchange.close();
        }
    }

    /** Write an error body, swallowing any secondary IO failure so we never mask the original problem. */
    private static void safeWriteError(HttpExchange exchange, int status, String code, String message) {
        try {
            Http.writeError(exchange, status, code, message);
        } catch (IOException ignored) {
            // The client likely disconnected; nothing useful we can do here.
        }
    }
}
