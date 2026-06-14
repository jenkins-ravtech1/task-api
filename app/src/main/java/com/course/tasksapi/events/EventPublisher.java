package com.course.tasksapi.events;

import com.course.tasksapi.model.Task;

/**
 * Publishes domain events (PRD FR-7). Today there is exactly one event:
 * {@code TASK_CREATED}, emitted after a task is successfully created.
 *
 * <p>Like {@link com.course.tasksapi.repo.TaskRepository}, this is an interface so
 * the rest of the app does not care HOW events are delivered. Session 1 uses a
 * no-op; session 5 swaps in an SQS-backed implementation.
 *
 * <p>Important rule: publishing is best-effort. A failure to publish must NOT
 * fail the user's request — the task was already saved. Implementations should
 * not throw for transient delivery problems (the caller also guards this).
 */
public interface EventPublisher {

    /** Announce that a task was created. */
    void taskCreated(Task task);
}
