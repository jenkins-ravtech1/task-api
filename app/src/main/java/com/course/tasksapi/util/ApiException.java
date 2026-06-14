package com.course.tasksapi.util;

/**
 * An error that should be turned into an HTTP response with a specific status
 * and the standard error body {@code {"error":"<CODE>","message":"..."}} (PRD FR-3).
 *
 * <p>Handlers simply {@code throw} one of these; the {@code LoggingHandler}
 * decorator catches it, writes the JSON body, and records the status. This keeps
 * error handling in ONE place instead of scattered try/catch blocks.
 */
public class ApiException extends RuntimeException {

    private final int status;
    private final String code;

    public ApiException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public int status() {
        return status;
    }

    public String code() {
        return code;
    }

    // Convenience factories for the cases this API actually returns. Using these
    // keeps status codes and machine-readable codes consistent across handlers.

    public static ApiException validation(String message) {
        return new ApiException(400, "VALIDATION", message);
    }

    public static ApiException badRequest(String message) {
        return new ApiException(400, "BAD_REQUEST", message);
    }

    public static ApiException notFound(String message) {
        return new ApiException(404, "NOT_FOUND", message);
    }

    public static ApiException methodNotAllowed(String message) {
        return new ApiException(405, "METHOD_NOT_ALLOWED", message);
    }

    public static ApiException unsupportedMediaType(String message) {
        return new ApiException(415, "UNSUPPORTED_MEDIA_TYPE", message);
    }
}
