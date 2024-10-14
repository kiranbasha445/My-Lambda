import { Handler } from 'aws-lambda';

interface LambdaEvent {
  // Define your event structure based on the type of event triggering the Lambda
  key: string;
}

export const handler: Handler = async (event: LambdaEvent) => {
  try {
    console.log('Received event:', JSON.stringify(event, null, 2));

    // Extract relevant data from the event
    const { key } = event;

    // Example logic - you can replace this with your actual functionality
    console.log(`Processing event for key: ${key}`);

    // Simulate success
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Lambda executed successfully',
        input: key
      })
    };
  } catch (error) {
    console.error('Error processing event:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Lambda execution failed',
        error: (error as Error).message
      })
    };
  }
};
