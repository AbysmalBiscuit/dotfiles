function cou --wraps=codex --description 'alias cou=codex on gpt-6-astra at ultra reasoning'
    codex --model gpt-6-astra --config model_reasoning_effort="ultra" $argv
end
