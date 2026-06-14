package com.course.tasksevents;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;

/**
 * AWS Lambda that consumes TASK_CREATED messages from the task-events SQS queue.
 *
 * <p>SESSION 4 (this stub): receive a batch of SQS messages and log each body.
 * That is enough to wire up the Terraform (event source mapping → Lambda) and
 * prove the trigger works.
 *
 * <p>SESSION 5 will flesh this out to: parse the JSON event, publish a
 * notification to SNS, be idempotent, and use partial-batch responses so one bad
 * message does not re-deliver the whole batch.
 *
 * <p>AWS invokes this by the handler reference {@code com.course.tasksevents.Handler}
 * (configured in lambda.tf), which calls {@link #handleRequest}.
 */
public class Handler implements RequestHandler<SQSEvent, Void> {

    @Override
    public Void handleRequest(SQSEvent event, Context context) {
        for (SQSEvent.SQSMessage message : event.getRecords()) {
            context.getLogger().log("Received SQS message: " + message.getBody());
        }
        return null;
    }
}
