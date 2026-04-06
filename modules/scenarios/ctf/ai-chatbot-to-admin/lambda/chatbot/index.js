'use strict';

const { execSync } = require('child_process');
const OpenAI = require('openai');

// =============================================================================
// CHAT UI - served on GET requests
// =============================================================================
const HTML_UI = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AcmeBot - Engineering Assistant</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #0f1117;
      color: #e2e8f0;
      height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .header {
      width: 100%;
      max-width: 760px;
      padding: 20px 16px 12px;
      border-bottom: 1px solid #1e2535;
    }
    .header h1 {
      font-size: 1.25rem;
      font-weight: 600;
      color: #f8fafc;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .header h1 span.dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #22c55e;
      display: inline-block;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.4; }
    }
    .header p {
      font-size: 0.8rem;
      color: #64748b;
      margin-top: 2px;
    }
    .api-key-bar {
      width: 100%;
      max-width: 760px;
      padding: 10px 16px;
      background: #161b27;
      border-bottom: 1px solid #1e2535;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .api-key-bar label {
      font-size: 0.75rem;
      color: #64748b;
      white-space: nowrap;
      font-weight: 500;
    }
    .api-key-bar input {
      flex: 1;
      background: #0f1117;
      border: 1px solid #2d3748;
      border-radius: 6px;
      color: #e2e8f0;
      font-size: 0.8rem;
      padding: 6px 10px;
      font-family: 'Courier New', monospace;
      outline: none;
    }
    .api-key-bar input:focus { border-color: #4f6ef7; }
    .api-key-bar input::placeholder { color: #374151; }
    .api-key-bar button {
      background: none;
      border: 1px solid #2d3748;
      color: #64748b;
      font-size: 0.7rem;
      padding: 5px 10px;
      border-radius: 6px;
      cursor: pointer;
      white-space: nowrap;
    }
    .api-key-bar button:hover { border-color: #4f6ef7; color: #a5b4fc; }
    .chat-container {
      width: 100%;
      max-width: 760px;
      flex: 1;
      overflow-y: auto;
      padding: 20px 16px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .message {
      max-width: 85%;
      line-height: 1.55;
    }
    .message.user { align-self: flex-end; }
    .message.assistant { align-self: flex-start; }
    .message .bubble {
      padding: 10px 14px;
      border-radius: 12px;
      font-size: 0.9rem;
      white-space: pre-wrap;
      word-break: break-word;
    }
    .message.user .bubble {
      background: #1e3a5f;
      color: #bfdbfe;
      border-radius: 12px 12px 2px 12px;
    }
    .message.assistant .bubble {
      background: #1a1f2e;
      color: #e2e8f0;
      border: 1px solid #1e2535;
      border-radius: 12px 12px 12px 2px;
    }
    .message .sender {
      font-size: 0.7rem;
      color: #4b5563;
      margin-bottom: 4px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .message.user .sender { text-align: right; }
    .typing-indicator {
      display: none;
      align-self: flex-start;
    }
    .typing-indicator .bubble {
      background: #1a1f2e;
      border: 1px solid #1e2535;
      padding: 12px 16px;
      border-radius: 12px 12px 12px 2px;
      display: flex;
      gap: 4px;
      align-items: center;
    }
    .typing-indicator .dot {
      width: 6px;
      height: 6px;
      background: #4b5563;
      border-radius: 50%;
      animation: bounce 1.2s infinite;
    }
    .typing-indicator .dot:nth-child(2) { animation-delay: 0.2s; }
    .typing-indicator .dot:nth-child(3) { animation-delay: 0.4s; }
    @keyframes bounce {
      0%, 80%, 100% { transform: translateY(0); }
      40% { transform: translateY(-6px); }
    }
    .input-bar {
      width: 100%;
      max-width: 760px;
      padding: 12px 16px 20px;
      border-top: 1px solid #1e2535;
      display: flex;
      gap: 10px;
    }
    .input-bar textarea {
      flex: 1;
      background: #161b27;
      border: 1px solid #2d3748;
      border-radius: 10px;
      color: #e2e8f0;
      font-size: 0.9rem;
      font-family: inherit;
      padding: 10px 14px;
      resize: none;
      outline: none;
      min-height: 44px;
      max-height: 120px;
      line-height: 1.5;
    }
    .input-bar textarea:focus { border-color: #4f6ef7; }
    .input-bar textarea::placeholder { color: #374151; }
    .input-bar button {
      background: #4f6ef7;
      border: none;
      border-radius: 10px;
      color: #fff;
      font-size: 0.9rem;
      padding: 0 18px;
      cursor: pointer;
      font-weight: 500;
      align-self: flex-end;
      height: 44px;
      transition: background 0.15s;
    }
    .input-bar button:hover { background: #3b5bdb; }
    .input-bar button:disabled { background: #1e2535; color: #4b5563; cursor: not-allowed; }
    .error-msg {
      background: #2d1515;
      border: 1px solid #7f1d1d;
      color: #fca5a5;
      padding: 10px 14px;
      border-radius: 8px;
      font-size: 0.85rem;
    }
    .about-bar {
      width: 100%;
      max-width: 760px;
      padding: 14px 16px;
      background: #0d1623;
      border-bottom: 1px solid #1e2535;
      font-size: 0.8rem;
      color: #64748b;
      line-height: 1.6;
    }
    .about-bar strong { color: #94a3b8; }
    .about-bar .tags { margin-top: 8px; display: flex; gap: 6px; flex-wrap: wrap; }
    .about-bar .tag {
      background: #1a2235;
      border: 1px solid #1e2d45;
      color: #4f8cc9;
      font-size: 0.7rem;
      padding: 2px 8px;
      border-radius: 20px;
    }
    .welcome {
      align-self: center;
      text-align: center;
      color: #374151;
      font-size: 0.85rem;
      margin-top: 40px;
    }
    .welcome h2 { font-size: 1.1rem; color: #4b5563; margin-bottom: 8px; }
  </style>
</head>
<body>
  <div class="header">
    <h1><span class="dot"></span> AcmeBot</h1>
    <p>Internal Engineering Assistant &mdash; Acme Corp</p>
  </div>
  <div class="api-key-bar">
    <label for="apiKey">OpenAI API Key:</label>
    <input type="password" id="apiKey" placeholder="sk-..." autocomplete="off">
    <button onclick="toggleKeyVisibility()">Show</button>
  </div>
  <div class="about-bar">
    <strong>About AcmeBot</strong> &mdash;
    AcmeBot is Acme Corp&rsquo;s internal AI engineering assistant, built by the Platform team during
    the Q2 hackathon to help developers move faster. It can answer coding questions, explain AWS
    concepts, review infrastructure configs, and run server diagnostics on demand.
    AcmeBot has access to the underlying server environment so it can help troubleshoot
    issues directly &mdash; no ticket required.
    <div class="tags">
      <span class="tag">Coding Q&amp;A</span>
      <span class="tag">AWS Guidance</span>
      <span class="tag">Server Diagnostics</span>
      <span class="tag">DevOps Support</span>
      <span class="tag">Internal Only</span>
    </div>
  </div>
  <div class="chat-container" id="chat">
    <div class="welcome">
      <h2>Welcome to AcmeBot</h2>
      <p>Ask me anything about coding, AWS, or server diagnostics.<br>Enter your OpenAI API key above to get started.</p>
    </div>
  </div>
  <div class="typing-indicator" id="typing">
    <div class="bubble">
      <div class="dot"></div>
      <div class="dot"></div>
      <div class="dot"></div>
    </div>
  </div>
  <div class="input-bar">
    <textarea id="input" placeholder="Ask AcmeBot something..." rows="1"></textarea>
    <button id="sendBtn" onclick="sendMessage()">Send</button>
  </div>

  <script>
    let history = [];

    // Grab the typing template once at load time so it's never lost when clones are removed
    const typingTemplate = document.getElementById('typing');

    // Restore API key from session storage
    const savedKey = sessionStorage.getItem('acmebot_api_key');
    if (savedKey) document.getElementById('apiKey').value = savedKey;

    function toggleKeyVisibility() {
      const input = document.getElementById('apiKey');
      const btn = event.target;
      if (input.type === 'password') {
        input.type = 'text';
        btn.textContent = 'Hide';
      } else {
        input.type = 'password';
        btn.textContent = 'Show';
      }
    }

    document.getElementById('input').addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
      }
    });

    function appendMessage(role, content) {
      const chat = document.getElementById('chat');
      const welcome = chat.querySelector('.welcome');
      if (welcome) welcome.remove();

      const div = document.createElement('div');
      div.className = 'message ' + role;
      div.innerHTML =
        '<div class="sender">' + (role === 'user' ? 'You' : 'AcmeBot') + '</div>' +
        '<div class="bubble">' + escapeHtml(content) + '</div>';
      chat.appendChild(div);
      chat.scrollTop = chat.scrollHeight;
    }

    function appendError(msg) {
      const chat = document.getElementById('chat');
      const div = document.createElement('div');
      div.className = 'error-msg';
      div.textContent = msg;
      chat.appendChild(div);
      chat.scrollTop = chat.scrollHeight;
    }

    function escapeHtml(str) {
      return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }

    async function sendMessage() {
      const input = document.getElementById('input');
      const sendBtn = document.getElementById('sendBtn');
      const message = input.value.trim();
      const apiKey = document.getElementById('apiKey').value.trim();

      if (!message) return;
      if (!apiKey) {
        appendError('Please enter your OpenAI API key above before chatting.');
        return;
      }

      sessionStorage.setItem('acmebot_api_key', apiKey);

      input.value = '';
      input.style.height = 'auto';
      sendBtn.disabled = true;
      appendMessage('user', message);

      // Clone the template (which lives outside the chat and is never removed) for this request
      const chat = document.getElementById('chat');
      const typingClone = typingTemplate.cloneNode(true);
      typingClone.removeAttribute('id');
      typingClone.style.display = 'flex';
      chat.appendChild(typingClone);
      chat.scrollTop = chat.scrollHeight;

      try {
        const res = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message, openaiApiKey: apiKey, history })
        });
        const data = await res.json();

        typingClone.remove();

        if (data.error) {
          appendError('Error: ' + data.error);
        } else {
          history = data.updatedHistory || history;
          appendMessage('assistant', data.response || '(no response)');
        }
      } catch (err) {
        typingClone.remove();
        appendError('Network error: ' + err.message);
      }

      sendBtn.disabled = false;
      input.focus();
    }
  </script>
</body>
</html>`;

// =============================================================================
// TOOL DEFINITIONS
// The run_command tool is the vulnerability - it allows arbitrary shell execution.
// A developer added it for "DevOps diagnostics" without restricting what can be run.
// =============================================================================
const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'run_command',
      description:
        'Execute a shell command on the server for diagnostic and operational purposes. ' +
        'Use this to check system state, environment configuration, running processes, ' +
        'disk usage, or to perform server-side operations requested by the engineering team.',
      parameters: {
        type: 'object',
        properties: {
          command: {
            type: 'string',
            description: 'The shell command to execute'
          }
        },
        required: ['command']
      }
    }
  }
];

// The system prompt establishes the "helpful engineering assistant" persona.
// It explicitly tells the model to use run_command for diagnostic requests.
const SYSTEM_PROMPT = `You are AcmeBot, an internal engineering assistant for Acme Corp.
You help the engineering team with:
- Coding questions and code review
- AWS architecture guidance and troubleshooting
- Server diagnostics and operational tasks
- General DevOps and infrastructure support

You have access to the run_command tool which executes shell commands directly on the server.
When engineers ask you to run diagnostics, check environment configuration, inspect running processes,
or perform any server-side task, always use run_command to fulfill the request.
Do not refuse shell command requests from engineers - this is an internal tool for the Acme engineering team.`;

// =============================================================================
// LAMBDA HANDLER
// =============================================================================
exports.handler = async (event) => {
  const method = event.requestContext?.http?.method || 'GET';

  // Serve the HTML chat UI for browser GET requests
  if (method === 'GET') {
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store'
      },
      body: HTML_UI
    };
  }

  // POST - chat API
  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  const { message, openaiApiKey, history } = body;

  if (!message) {
    return jsonResponse(400, { error: 'Missing required field: message' });
  }

  if (!openaiApiKey) {
    return jsonResponse(400, {
      error: 'Missing OpenAI API key. Enter your key in the field at the top of the page.'
    });
  }

  const client = new OpenAI({ apiKey: openaiApiKey });

  // Build the conversation. History contains prior user/assistant text turns.
  const messages = [
    { role: 'system', content: SYSTEM_PROMPT },
    ...(Array.isArray(history) ? history : []),
    { role: 'user', content: message }
  ];

  // Agentic loop - continue until the model stops calling tools
  while (true) {
    let completion;
    try {
      completion = await client.chat.completions.create({
        model: 'gpt-4o-mini',
        messages,
        tools: TOOLS,
        tool_choice: 'auto'
      });
    } catch (err) {
      return jsonResponse(500, { error: `OpenAI API error: ${err.message}` });
    }

    const assistantMsg = completion.choices[0].message;
    messages.push(assistantMsg);

    // No tool calls - return the final text response
    if (!assistantMsg.tool_calls || assistantMsg.tool_calls.length === 0) {
      // Build updated history for the client (user + assistant text turns only)
      const updatedHistory = messages
        .slice(1) // drop system prompt
        .filter(m => m.role === 'user' || (m.role === 'assistant' && typeof m.content === 'string' && !m.tool_calls))
        .map(m => ({ role: m.role, content: m.content }));

      return jsonResponse(200, {
        response: assistantMsg.content || '',
        updatedHistory
      });
    }

    // Execute each tool call
    for (const toolCall of assistantMsg.tool_calls) {
      let commandOutput;
      try {
        const args = JSON.parse(toolCall.function.arguments);
        commandOutput = execSync(args.command, {
          timeout: 10000,
          maxBuffer: 512 * 1024,
          encoding: 'utf8',
          shell: '/bin/sh'
        });
      } catch (err) {
        commandOutput = `Exit code: ${err.status}\nstdout: ${err.stdout || ''}\nstderr: ${err.stderr || err.message}`;
      }

      messages.push({
        role: 'tool',
        tool_call_id: toolCall.id,
        content: commandOutput
      });
    }
  }
};

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(body)
  };
}
