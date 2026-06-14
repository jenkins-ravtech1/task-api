package com.course.tasksapi.model;

import com.course.tasksapi.util.Json;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Verifies the JSON shape of a Task matches the contract (PRD §8.2). */
class TaskJsonTest {

    @Test
    void serializesAllFieldsWithExpectedNames() {
        Task task = Task.create("Learn Docker", "containers 101");

        JsonNode json = Json.parse(Json.toJson(task));

        assertEquals(task.getId(), json.get("id").asText());
        assertEquals("Learn Docker", json.get("title").asText());
        assertEquals("containers 101", json.get("description").asText());
        assertFalse(json.get("done").asBoolean());
        // createdAt should be an ISO-8601 instant ending in Z (UTC).
        assertTrue(json.get("createdAt").asText().endsWith("Z"));
    }

    @Test
    void newTaskHasServerGeneratedIdAndTimestampAndIsNotDone() {
        Task task = Task.create("x", null);

        assertFalse(task.getId().isBlank());
        assertFalse(task.getCreatedAt().isBlank());
        assertFalse(task.isDone());
    }

    @Test
    void deserializeIgnoresUnknownFields() {
        // A client might POST extra fields; we must not blow up on them.
        String body = "{\"title\":\"t\",\"description\":\"d\",\"bogus\":123}";

        Task task = Json.mapper().convertValue(Json.parse(body), Task.class);

        assertEquals("t", task.getTitle());
        assertEquals("d", task.getDescription());
    }
}
