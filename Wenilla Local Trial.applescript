-- Double-click wrapper for the wenilla local-trial launcher.
-- Opens Terminal so the live extract/up output stays visible.
-- The launcher binary path is the compiled-in checkout; edit it if you move the repo.
tell application "Terminal"
	activate
	do script "/Users/kubbo.ai/github/wenilla-realm/wenilla-launch"
end tell
