'use strict';

// Acme Data Processor Lambda
// This Lambda runs scheduled data processing jobs for the Acme platform.
// It has broad AWS permissions because it manages data across multiple services.
//
// In ctf-002, an attacker who extracts credentials from the chatbot Lambda
// can update this function's code to exfiltrate these credentials, since
// the attacker's chatbot role has lambda:UpdateFunctionCode + lambda:InvokeFunction.

exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({
      message: 'Acme Data Processor: job completed successfully',
      jobId: event.jobId || 'batch-default',
      timestamp: new Date().toISOString()
    })
  };
};
