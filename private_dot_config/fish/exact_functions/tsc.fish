function tsc --wraps='bunx tsc' --description 'alias tsc=bun tsc --noEmit -p tsconfig.json'
    bunx tsc --noEmit -p tsconfig.json
end
