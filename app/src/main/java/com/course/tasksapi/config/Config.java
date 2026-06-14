package com.course.tasksapi.config;

/**
 * Application configuration.
 *
 * <p>Rule (PRD FR-9): the app reads configuration ONLY from environment
 * variables — never from hard-coded values or committed files. This single
 * class is the one place that touches {@link System#getenv}. Everything else
 * receives a {@code Config} object, which makes the app easy to test and makes
 * the full list of knobs visible in one spot.
 *
 * <p>The full table of variables lives in the README and the PRD (§10). Defaults
 * here must match that table.
 */
public final class Config {

    private final int port;
    private final String version;
    private final String storage;
    private final String logLevel;

    // AWS-related settings. They are unused in session 1 (memory mode) but live
    // here from the start because this class is the single env-reader. The
    // factories (Repositories / Publishers) decide when to use them.
    private final String awsRegion;          // may be null locally
    private final String awsEndpointUrl;     // set to LocalStack URL locally; null in AWS
    private final String tasksTable;
    private final String taskEventsQueueUrl; // null => no SQS publishing
    private final String notificationsTopicArn;

    // Package-visible constructor; use the factories below.
    Config(int port, String version, String storage, String logLevel,
           String awsRegion, String awsEndpointUrl, String tasksTable,
           String taskEventsQueueUrl, String notificationsTopicArn) {
        this.port = port;
        this.version = version;
        this.storage = storage;
        this.logLevel = logLevel;
        this.awsRegion = awsRegion;
        this.awsEndpointUrl = awsEndpointUrl;
        this.tasksTable = tasksTable;
        this.taskEventsQueueUrl = taskEventsQueueUrl;
        this.notificationsTopicArn = notificationsTopicArn;
    }

    /** Build a Config from the process environment. This is what {@code App.main} uses. */
    public static Config fromEnv() {
        return new Config(
                parseInt(env("APP_PORT", "8080"), 8080),
                env("APP_VERSION", "dev"),
                env("STORAGE", "memory"),
                env("LOG_LEVEL", "INFO"),
                envOrNull("AWS_REGION"),
                envOrNull("AWS_ENDPOINT_URL"),
                env("TASKS_TABLE", "tasks"),
                envOrNull("TASK_EVENTS_QUEUE_URL"),
                envOrNull("NOTIFICATIONS_TOPIC_ARN"));
    }

    /**
     * Convenience factory for tests / manual wiring. The app always uses
     * {@link #fromEnv()}; tests use this to pick an ephemeral port (0) and a
     * known version without touching the real environment.
     */
    public static Config of(int port, String version) {
        return new Config(port, version, "memory", "INFO",
                null, null, "tasks", null, null);
    }

    public int port() { return port; }
    public String version() { return version; }
    public String storage() { return storage; }
    public String logLevel() { return logLevel; }
    public String awsRegion() { return awsRegion; }
    public String awsEndpointUrl() { return awsEndpointUrl; }
    public String tasksTable() { return tasksTable; }
    public String taskEventsQueueUrl() { return taskEventsQueueUrl; }
    public String notificationsTopicArn() { return notificationsTopicArn; }

    // --- small helpers -------------------------------------------------------

    /** Returns the env var, or {@code def} when unset or blank. */
    private static String env(String name, String def) {
        String v = System.getenv(name);
        return (v == null || v.isBlank()) ? def : v.trim();
    }

    /** Returns the env var trimmed, or {@code null} when unset/blank. */
    private static String envOrNull(String name) {
        String v = System.getenv(name);
        return (v == null || v.isBlank()) ? null : v.trim();
    }

    private static int parseInt(String value, int def) {
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            return def;
        }
    }
}
