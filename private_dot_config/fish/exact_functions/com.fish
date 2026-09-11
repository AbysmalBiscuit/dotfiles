function com --wraps=codex --description 'alias com=codex on gpt-5.6-luna at max reasoning'
    codex --model gpt-5.6-luna --config model_reasoning_effort="max" $argv
end
