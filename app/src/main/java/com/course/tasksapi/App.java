package com.course.tasksapi;

import com.course.tasksapi.config.Config;
import com.course.tasksapi.events.EventPublisher;
import com.course.tasksapi.events.Publishers;
import com.course.tasksapi.handlers.FallbackHandler;
import com.course.tasksapi.handlers.HealthHandler;
import com.course.tasksapi.handlers.LoggingHandler;
import com.course.tasksapi.handlers.TasksHandler;
import com.course.tasksapi.repo.Repositories;
import com.course.tasksapi.repo.TaskRepository;
import com.course.tasksapi.util.Logging;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Application entry point: build the configuration, wire up storage + events,
 * register the routes, and start the built-in {@link HttpServer}.
 *
 * <p>There is deliberately no web framework. The JDK ships an HTTP server in
 * {@code com.sun.net.httpserver}; we map URL prefixes ("contexts") to handlers
 * and serve. Each handler is wrapped in {@link LoggingHandler} so every request
 * gets an id, structured log line, and consistent error handling.
 */
public class App {

    public static void main(String[] args) throws IOException {
        Config cfg = Config.fromEnv();
        Logging.configure(cfg.logLevel());

        // Pick implementations based on environment (memory vs dynamodb, noop vs sqs).
        TaskRepository repo = Repositories.create(cfg);
        EventPublisher events = Publishers.create(cfg);

        HttpServer server = createServer(cfg, repo, events);

        // Graceful shutdown: when the container/host sends SIGTERM, stop accepting
        // new requests and give in-flight ones up to 2 seconds to finish (FR-8).
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            Logging.info("Shutting down Tasks API...");
            server.stop(2);
        }));

        server.start();
        Logging.info("Tasks API listening on port " + cfg.port()
                + " (storage=" + cfg.storage() + ", version=" + cfg.version() + ")");
    }

    /**
     * Build a fully-wired (but not started) server. Factored out from {@code main}
     * so tests can start it on an ephemeral port (port 0) with in-memory storage.
     */
    public static HttpServer createServer(Config cfg, TaskRepository repo, EventPublisher events) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(cfg.port()), 0);

        // A bounded thread pool (FR-8): the server handles up to 16 requests
        // concurrently and queues the rest, rather than spawning unbounded threads.
        ExecutorService pool = Executors.newFixedThreadPool(16);
        server.setExecutor(pool);

        // Routes. Order does not matter — HttpServer picks the longest prefix match.
        server.createContext("/health", new LoggingHandler(new HealthHandler(cfg)));
        server.createContext("/tasks", new LoggingHandler(new TasksHandler(repo, events)));
        // Root catch-all so unknown paths return our JSON 404 (not HttpServer's text one).
        server.createContext("/", new LoggingHandler(new FallbackHandler()));

        return server;
    }
}
