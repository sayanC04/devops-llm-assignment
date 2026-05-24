#!/bin/bash
curl -s -X POST http://10.0.2.198:3111/v1/chat/completions -H "Content-Type: application/json" -d '{"messages": [{"role": "user", "content": "Explain quantum computing in one short sentence."}]}'
