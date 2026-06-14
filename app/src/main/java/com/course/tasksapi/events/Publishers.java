package com.course.tasksapi.events;

import com.course.tasksapi.config.Config;

/**
 * Chooses which {@link EventPublisher} to use (PRD FR-7):
 * <ul>
 *   <li>no {@code TASK_EVENTS_QUEUE_URL} → {@link NoOpEventPublisher} (default)</li>
 *   <li>queue URL set → SQS publisher (added in session 5 / M5)</li>
 * </ul>
 */
public final class Publishers {

    private Publishers() {
    }

    public static EventPublisher create(Config cfg) {
        String queueUrl = cfg.taskEventsQueueUrl();
        if (queueUrl != null && !queueUrl.isBlank()) {
            return new SqsEventPublisher(cfg);
        }
        return new NoOpEventPublisher();
    }
}
