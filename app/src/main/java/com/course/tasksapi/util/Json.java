package com.course.tasksapi.util;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Tiny wrapper around a single, shared Jackson {@link ObjectMapper}.
 *
 * <p>Creating an ObjectMapper is relatively expensive and it is thread-safe once
 * configured, so the idiomatic pattern is to build ONE and reuse it everywhere.
 */
public final class Json {

    private static final ObjectMapper MAPPER = build();

    private Json() {
    }

    private static ObjectMapper build() {
        ObjectMapper m = new ObjectMapper();
        // Be lenient about extra fields a client sends (e.g. an "id" on POST):
        // ignore them rather than failing the whole request.
        m.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        return m;
    }

    public static ObjectMapper mapper() {
        return MAPPER;
    }

    /** Serialize any object to a compact JSON string. */
    public static String toJson(Object value) {
        try {
            return MAPPER.writeValueAsString(value);
        } catch (Exception e) {
            // Serializing our own DTOs should never fail; if it does it is a bug.
            throw new IllegalStateException("Failed to serialize to JSON", e);
        }
    }

    /** Parse a JSON string into a navigable tree. Throws on malformed input. */
    public static JsonNode parse(String json) {
        try {
            return MAPPER.readTree(json);
        } catch (Exception e) {
            throw new IllegalArgumentException("Malformed JSON: " + e.getMessage(), e);
        }
    }
}
