package com.course.tasksapi.repo;

import com.course.tasksapi.model.Task;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Simplest possible {@link TaskRepository}: a thread-safe in-memory map.
 *
 * <p>Used in session 1 and in unit tests. Data lives only as long as the process
 * — restart the app and it is gone. That is fine for learning and for tests, and
 * it lets students run the API with zero infrastructure.
 *
 * <p>{@link ConcurrentHashMap} makes this safe to use from the HttpServer's pool
 * of request threads without explicit locking.
 */
public class InMemoryTaskRepository implements TaskRepository {

    private final ConcurrentHashMap<String, Task> store = new ConcurrentHashMap<>();

    @Override
    public List<Task> findAll() {
        // Return a copy so callers can't mutate our internal collection.
        return new ArrayList<>(store.values());
    }

    @Override
    public Optional<Task> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }

    @Override
    public Task save(Task task) {
        store.put(task.getId(), task);
        return task;
    }

    @Override
    public boolean deleteById(String id) {
        return store.remove(id) != null;
    }
}
