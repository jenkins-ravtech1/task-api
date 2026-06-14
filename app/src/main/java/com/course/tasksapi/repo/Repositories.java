package com.course.tasksapi.repo;

import com.course.tasksapi.config.Config;

/**
 * Chooses which {@link TaskRepository} to use, based on the {@code STORAGE}
 * environment variable (PRD FR-6):
 * <ul>
 *   <li>{@code memory}   → {@link InMemoryTaskRepository} (default; session 1)</li>
 *   <li>{@code dynamodb} → DynamoDB-backed repo (added in session 5 / M5)</li>
 * </ul>
 *
 * <p>This "factory" is the seam that lets us grow the app without touching the
 * handlers: they always receive a {@code TaskRepository}, never a concrete class.
 */
public final class Repositories {

    private Repositories() {
    }

    public static TaskRepository create(Config cfg) {
        String storage = cfg.storage();
        switch (storage) {
            case "memory":
                return new InMemoryTaskRepository();
            case "dynamodb":
                // Replaced in session 5 with: return new DynamoDbTaskRepository(cfg);
                throw new UnsupportedOperationException(
                        "STORAGE=dynamodb is introduced in session 5. Use STORAGE=memory for now.");
            default:
                throw new IllegalArgumentException(
                        "Unknown STORAGE value: '" + storage + "' (expected 'memory' or 'dynamodb')");
        }
    }
}
