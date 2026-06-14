package com.course.tasksapi.repo;

import com.course.tasksapi.model.Task;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Unit tests for the in-memory storage (PRD §16). */
class InMemoryTaskRepositoryTest {

    private final TaskRepository repo = new InMemoryTaskRepository();

    @Test
    void savesAndFindsById() {
        Task task = Task.create("Learn Docker", null);

        repo.save(task);

        Optional<Task> found = repo.findById(task.getId());
        assertTrue(found.isPresent());
        assertEquals("Learn Docker", found.get().getTitle());
    }

    @Test
    void findByIdReturnsEmptyWhenMissing() {
        assertTrue(repo.findById("does-not-exist").isEmpty());
    }

    @Test
    void findAllCountsEverythingSaved() {
        repo.save(Task.create("a", null));
        repo.save(Task.create("b", null));

        assertEquals(2, repo.findAll().size());
    }

    @Test
    void deleteRemovesAndReportsWhetherAnythingWasRemoved() {
        Task task = repo.save(Task.create("temp", null));

        assertTrue(repo.deleteById(task.getId()));   // existed → removed
        assertFalse(repo.deleteById(task.getId()));   // already gone → false
        assertTrue(repo.findById(task.getId()).isEmpty());
    }

    @Test
    void saveReplacesExistingTask() {
        Task task = repo.save(Task.create("original", null));

        task.setTitle("updated");
        task.setDone(true);
        repo.save(task);

        Task reloaded = repo.findById(task.getId()).orElseThrow();
        assertEquals("updated", reloaded.getTitle());
        assertTrue(reloaded.isDone());
        assertEquals(1, repo.findAll().size()); // replaced, not duplicated
    }
}
