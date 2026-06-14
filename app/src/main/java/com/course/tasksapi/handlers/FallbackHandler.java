package com.course.tasksapi.handlers;

import com.course.tasksapi.util.ApiException;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;

/**
 * Catch-all handler registered at the root context {@code "/"}.
 *
 * <p>HttpServer routes a request to the context with the LONGEST matching path
 * prefix. Registering this at "/" means any request that didn't match "/health"
 * or "/tasks" lands here. Without it, HttpServer would send its own plain-text
 * 404 — which would break our rule that every response uses the JSON error shape
 * (FR-3). Throwing {@link ApiException} lets {@code LoggingHandler} render it.
 */
public class FallbackHandler implements HttpHandler {

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        throw ApiException.notFound(
                "No route for " + exchange.getRequestMethod() + " " + exchange.getRequestURI().getPath());
    }
}
