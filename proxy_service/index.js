const AWS = require('aws-sdk');
const lambda = new AWS.Lambda({
  region: 'eu-central-1'
});
exports.handler = async (event) => {
  let body;
  try {
    body = JSON.parse(event.body);
    const { image } = body;
    if (!image) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ error: 'Image is required' })
      };
    }
    const response = await lambda.invoke({
      FunctionName: process.env.TARGET_LAMBDA_FUNCTION_NAME,
      InvocationType: 'RequestResponse',
      Payload: JSON.stringify({ image })
    }).promise();
    console.log('Response :', JSON.stringify(response.Payload, null, 2));

    const result = JSON.parse(response.Payload);
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        message: 'Image processed successfully',
        result: result
      })
    };
  } catch (e) {
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ error: e.message })
    };
  }
}