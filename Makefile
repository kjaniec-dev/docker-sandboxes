.PHONY: test verify verify-opencode verify-agy rebuild rebuild-claude rebuild-codex rebuild-opencode rebuild-agy

test:
	./tests/run.sh

verify:
	./harnesses/claude-code/scripts/verify.sh

verify-opencode:
	./harnesses/opencode/scripts/verify.sh

verify-agy:
	./harnesses/antigravity-cli/scripts/verify.sh

rebuild:
	$(MAKE) rebuild-claude

rebuild-claude:
	./bin/claude-sbx-rebuild

rebuild-codex:
	./bin/codex-sbx-rebuild

rebuild-opencode:
	./bin/opencode-sbx-rebuild

rebuild-agy:
	./bin/agy-sbx-rebuild
