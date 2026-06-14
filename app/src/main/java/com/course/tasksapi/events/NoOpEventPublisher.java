package com.course.tasksapi.events;

import com.course.tasksapi.model.Task;
import com.course.tasksapi.util.Logging;

/**
 * The default {@link EventPublisher}: it does nothing (beyond a debug log).
 *
 * <p>Used whenever no queue is configured — session 1, unit tests, and any run
 * where {@code TASK_EVENTS_QUEUE_URL} is unset. It lets the create flow call
 * {@code events.taskCreated(...)} unconditionally without special-casing.
 */
public class NoOpEventPublisher implements EventPublisher {

    @Override
    public void taskCreated(Task task) {
        Logging.debug("NoOpEventPublisher: ignoring TASK_CREATED for task " + task.getId());
    }
}
