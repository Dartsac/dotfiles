-- lua/lsp/mason.lua
local M = {}

---Run after your *handlers* have been created
---@param handlers table  lsp.handlers module (contains .on_attach / .capabilities)
function M.setup(handlers)
  -- typescript‑tools is optional
  local ok, ts = pcall(require, "typescript-tools")
  if ok and not ts.__initialized then
    ts.__initialized = true -- mark so we don’t run again
    ts.setup({
      on_attach = handlers.on_attach,
      capabilities = handlers.capabilities,
    })
  end
end

return M
