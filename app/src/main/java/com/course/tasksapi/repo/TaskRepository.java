package com.course.tasksapi.repo;

import com.course.tasksapi.model.Task;

import java.util.List;
import java.util.Optional;

/**
 * Storage abstraction for tasks (PRD FR-6).
 *
 * <p>The HTTP handlers talk to this interface and never to a concrete database.
 * That is the whole point: in session 1 we plug in {@link InMemoryTaskRepository}
 * and in session 5 we swap in a DynamoDB-backed implementation — without changing
 * a single handler. Which one is used is decided by the {@code STORAGE} env var
 * in {@link Repositories}.
 */
public interface TaskRepository {

    /** All tasks (order is unspecified). */
    List<Task> findAll();

    /** The task with this id, or empty if none exists. */
    Optional<Task> findById(String id);

    /** Create or replace a task, returning the stored value. */
    Task save(Task task);

    /** Delete by id; returns true if something was actually removed. */
    boolean deleteById(String id);
}
