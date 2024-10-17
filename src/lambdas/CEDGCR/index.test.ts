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
        message: 'Lambda executed successfully done',
        input: 'test-key'
      })
    });
  });
});
