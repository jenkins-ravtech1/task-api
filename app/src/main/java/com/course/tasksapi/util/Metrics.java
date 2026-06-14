package com.course.tasksapi.util;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Emits metrics using CloudWatch EMF (Embedded Metric Format) — special JSON log
 * lines that CloudWatch automatically turns into metrics (PRD §15). The win:
 * one stdout line is BOTH a structured log (queryable in Logs Insights) AND a
 * metric, with no extra API calls or agents.
 *
 * <p>An EMF line looks like:
 * <pre>
 * { "_aws": { "Timestamp": 1718..., "CloudWatchMetrics": [ {
 *        "Namespace": "TasksApi", "Dimensions": [["Service"]],
 *        "Metrics": [ {"Name":"durationMs","Unit":"Milliseconds"} ] } ] },
 *   "Service": "tasks-api", "method": "GET", "status": 200, "durationMs": 12 }
 * </pre>
 *
 * <p>We emit two things: the per-request latency (which also carries the FR-4 log
 * fields) and a {@code TasksCreated} count on each successful create.
 *
 * <p>Locally (no CloudWatch) these are just JSON log lines — harmless.
 */
public final class Metrics {

    private static final String NAMESPACE = "TasksApi";
    private static final String SERVICE = "tasks-api";

    private Metrics() {
    }

    /**
     * Per-request line: the FR-4 fields (requestId/method/path/status/durationMs)
     * as properties, with {@code durationMs} also exposed as a CloudWatch metric.
     */
    public static void emitRequest(String requestId, String method, String path, int status, long durationMs) {
        System.out.println(buildRequest(requestId, method, path, status, durationMs));
    }

    /** Count metric emitted once per successful task creation. */
    public static void emitTaskCreated() {
        System.out.println(buildTaskCreated());
    }

    // --- builders (package-visible so tests can assert on the JSON) ----------

    static String buildRequest(String requestId, String method, String path, int status, long durationMs) {
        String level = status >= 500 ? "ERROR" : (status >= 400 ? "WARN" : "INFO");

        Map<String, Object> properties = new LinkedHashMap<>();
        properties.put("level", level);
        properties.put("requestId", requestId);
        properties.put("method", method);
        properties.put("path", path);
        properties.put("status", status);

        Map<String, Object> metricValues = new LinkedHashMap<>();
        metricValues.put("durationMs", durationMs);

        Map<String, String> metricUnits = new LinkedHashMap<>();
        metricUnits.put("durationMs", "Milliseconds");

        return build(properties, metricValues, metricUnits);
    }

    static String buildTaskCreated() {
        Map<String, Object> metricValues = new LinkedHashMap<>();
        metricValues.put("TasksCreated", 1);

        Map<String, String> metricUnits = new LinkedHashMap<>();
        metricUnits.put("TasksCreated", "Count");

        return build(new LinkedHashMap<>(), metricValues, metricUnits);
    }

    private static String build(Map<String, Object> properties,
                                Map<String, Object> metricValues,
                                Map<String, String> metricUnits) {
        // The CloudWatchMetrics directive: which fields are metrics, and their units.
        List<Map<String, String>> metricDefs = new ArrayList<>();
        for (Map.Entry<String, String> e : metricUnits.entrySet()) {
            Map<String, String> def = new LinkedHashMap<>();
            def.put("Name", e.getKey());
            def.put("Unit", e.getValue());
            metricDefs.add(def);
        }

        Map<String, Object> cwMetrics = new LinkedHashMap<>();
        cwMetrics.put("Namespace", NAMESPACE);
        cwMetrics.put("Dimensions", List.of(List.of("Service")));
        cwMetrics.put("Metrics", metricDefs);

        Map<String, Object> aws = new LinkedHashMap<>();
        aws.put("Timestamp", Instant.now().toEpochMilli());
        aws.put("CloudWatchMetrics", List.of(cwMetrics));

        Map<String, Object> doc = new LinkedHashMap<>();
        doc.put("_aws", aws);
        doc.put("ts", Instant.now().toString());
        doc.put("Service", SERVICE);
        properties.forEach(doc::put);
        metricValues.forEach(doc::put);

        return Json.toJson(doc);
    }
}
