package com.course.tasksapi.util;

import com.sun.net.httpserver.HttpExchange;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Small helpers for reading requests and writing responses with the raw JDK
 * {@link HttpExchange}. The HttpServer API is low-level (you write bytes to a
 * stream), so these helpers remove repetitive boilerplate from the handlers.
 */
public final class Http {

    public static final String CONTENT_TYPE = "Content-Type";
    public static final String APPLICATION_JSON = "application/json; charset=utf-8";

    private Http() {
    }

    /** Read the full request body as a UTF-8 string. */
    public static String readBody(HttpExchange exchange) throws IOException {
        try (InputStream in = exchange.getRequestBody()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /** Write {@code body} serialized as JSON with the given status code. */
    public static void writeJson(HttpExchange exchange, int status, Object body) throws IOException {
        byte[] bytes = Json.toJson(body).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set(CONTENT_TYPE, APPLICATION_JSON);
        // The 2nd arg is the body length; HttpServer needs it up front.
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    /** Write the standard error body {@code {"error","message"}} (PRD FR-3). */
    public static void writeError(HttpExchange exchange, int status, String code, String message) throws IOException {
        // LinkedHashMap keeps a stable, readable field order in the output.
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("error", code);
        body.put("message", message);
        writeJson(exchange, status, body);
    }

    /** Write a 204 No Content response (used by DELETE). */
    public static void writeNoContent(HttpExchange exchange) throws IOException {
        // -1 tells HttpServer there is no response body.
        exchange.sendResponseHeaders(204, -1);
        exchange.close();
    }
}
