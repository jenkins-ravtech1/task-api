package com.course.tasksapi.util;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Minimal structured (JSON) logger — one JSON object per line, written to stdout.
 *
 * <p>Why not java.util.logging or Logback? The PRD asks for structured JSON logs
 * with no heavy framework, because in the cloud these lines are shipped straight
 * to CloudWatch Logs and queried with Logs Insights. A single tiny helper keeps
 * the dependency list short and the behaviour obvious to a beginner.
 *
 * <p>Every line has at least {@code ts} (ISO-8601 UTC) and {@code level}. The
 * per-request line (see {@link #request}) carries exactly the fields required by
 * PRD FR-4: {@code requestId, method, path, status, durationMs}.
 */
public final class Logging {

    /** Severity levels, ordered. A message is printed when its level >= threshold. */
    public enum Level {
        DEBUG, INFO, WARN, ERROR
    }

    // The threshold is set once at startup from LOG_LEVEL. volatile = safe to read
    // from many request threads after main() configures it.
    private static volatile Level threshold = Level.INFO;

    private Logging() {
    }

    /** Set the minimum level to print (from the LOG_LEVEL env var). Unknown => INFO. */
    public static void configure(String level) {
        try {
            threshold = Level.valueOf(level.trim().toUpperCase());
        } catch (Exception e) {
            threshold = Level.INFO;
        }
    }

    public static void debug(String message) {
        log(Level.DEBUG, message, null, null);
    }

    public static void info(String message) {
        log(Level.INFO, message, null, null);
    }

    public static void warn(String message, Throwable error) {
        log(Level.WARN, message, null, error);
    }

    public static void error(String message, Throwable error, Map<String, Object> fields) {
        log(Level.ERROR, message, fields, error);
    }

    /**
     * Emit the one structured line that summarizes a finished HTTP request.
     * Level escalates with status so 5xx lines are easy to alarm/search on.
     */
    public static void request(String requestId, String method, String path, int status, long durationMs) {
        Level level = status >= 500 ? Level.ERROR : (status >= 400 ? Level.WARN : Level.INFO);
        if (level.ordinal() < threshold.ordinal()) {
            return;
        }
        Map<String, Object> line = new LinkedHashMap<>();
        line.put("ts", Instant.now().toString());
        line.put("level", level.name());
        line.put("requestId", requestId);
        line.put("method", method);
        line.put("path", path);
        line.put("status", status);
        line.put("durationMs", durationMs);
        System.out.println(Json.toJson(line));
    }

    // --- core ---------------------------------------------------------------

    private static void log(Level level, String message, Map<String, Object> fields, Throwable error) {
        if (level.ordinal() < threshold.ordinal()) {
            return;
        }
        Map<String, Object> line = new LinkedHashMap<>();
        line.put("ts", Instant.now().toString());
        line.put("level", level.name());
        line.put("message", message);
        if (fields != null) {
            line.putAll(fields);
        }
        if (error != null) {
            line.put("error", error.getClass().getSimpleName() + ": " + error.getMessage());
        }
        System.out.println(Json.toJson(line));
    }
}
