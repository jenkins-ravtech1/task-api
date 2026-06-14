package com.course.tasksapi.util;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** Verifies the EMF JSON structure CloudWatch relies on (PRD §15). */
class MetricsTest {

    @Test
    void requestEmfCarriesLatencyMetricAndFr4Fields() {
        JsonNode doc = Json.parse(Metrics.buildRequest("rid-1", "GET", "/tasks", 200, 12));

        // EMF envelope: namespace + the durationMs metric definition.
        JsonNode cw = doc.get("_aws").get("CloudWatchMetrics").get(0);
        assertEquals("TasksApi", cw.get("Namespace").asText());
        assertEquals("Service", cw.get("Dimensions").get(0).get(0).asText());
        assertEquals("durationMs", cw.get("Metrics").get(0).get("Name").asText());
        assertEquals("Milliseconds", cw.get("Metrics").get(0).get("Unit").asText());

        // FR-4 fields are present as properties, and the metric value is set.
        assertEquals("rid-1", doc.get("requestId").asText());
        assertEquals("GET", doc.get("method").asText());
        assertEquals("/tasks", doc.get("path").asText());
        assertEquals(200, doc.get("status").asInt());
        assertEquals(12, doc.get("durationMs").asInt());
        assertEquals("INFO", doc.get("level").asText());
    }

    @Test
    void serverErrorRequestIsLoggedAtErrorLevel() {
        JsonNode doc = Json.parse(Metrics.buildRequest("rid-2", "GET", "/tasks", 500, 3));
        assertEquals("ERROR", doc.get("level").asText());
    }

    @Test
    void taskCreatedEmfCarriesCountMetric() {
        JsonNode doc = Json.parse(Metrics.buildTaskCreated());

        JsonNode cw = doc.get("_aws").get("CloudWatchMetrics").get(0);
        assertEquals("TasksCreated", cw.get("Metrics").get(0).get("Name").asText());
        assertEquals("Count", cw.get("Metrics").get(0).get("Unit").asText());
        assertEquals(1, doc.get("TasksCreated").asInt());
        assertEquals("tasks-api", doc.get("Service").asText());
    }
}
