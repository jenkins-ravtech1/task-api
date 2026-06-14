package com.course.tasksapi.handlers;

import com.course.tasksapi.config.Config;
import com.course.tasksapi.util.ApiException;
import com.course.tasksapi.util.Http;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * {@code GET /health} → {@code 200 {"status":"UP","version":"<v>"}} (PRD §8.1).
 *
 * <p>Used by humans, by the Docker {@code HEALTHCHECK}, and by the CD smoke test
 * to confirm the service is alive and which version is running.
 */
public class HealthHandler implements HttpHandler {

    private final Config cfg;

    public HealthHandler(Config cfg) {
        this.cfg = cfg;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        // The "/health" context also receives look-alikes such as "/healthz"
        // because HttpServer matches by path prefix — reject anything that is not
        // exactly "/health".
        if (!exchange.getRequestURI().getPath().equals("/health")) {
            throw ApiException.notFound("No route for " + exchange.getRequestURI().getPath());
        }
        if (!exchange.getRequestMethod().equals("GET")) {
            exchange.getResponseHeaders().set("Allow", "GET");
            throw ApiException.methodNotAllowed("Only GET is supported on /health");
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", "UP");
        body.put("version", cfg.version());
        Http.writeJson(exchange, 200, body);
    }
}
