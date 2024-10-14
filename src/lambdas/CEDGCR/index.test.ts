import { handler } from './index';
import { Context, Callback } from 'aws-lambda';

describe('Lambda Function Tests', () => {
  const mockEvent = {
    key: 'test-key'
  };

  const mockContext: Context = {} as Context;
  const mockCallback: Callback = () => { };

  it('should return a success response', async () => {
    const response = await handler(mockEvent, mockContext, mockCallback);

    expect(response).toEqual({
      statusCode: 200,
      body: JSON.stringify({
        message: 'Lambda executed successfully',
        input: 'test-key'
      })
    });
  });

  it('should handle errors correctly', async () => {
    // Simulate an error by throwing inside the handler (e.g., missing 'key' in event)
    const invalidEvent = {}; // Event with missing 'key'

    const response = await handler(invalidEvent as any, mockContext, mockCallback);

    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body).message).toBe('Lambda executed successfully');
  });
});
