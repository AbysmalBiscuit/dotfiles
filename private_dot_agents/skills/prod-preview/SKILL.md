---
name: prod-preview-pp
description: Add PR labels required to deploy a prod preview instance
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet
---
Add these labels to PR to get live preview:
- deploy:labos
- prod-sync
