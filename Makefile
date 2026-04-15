yapl4: y.tab.c lex.yy.c
	gcc -o yapl4 y.tab.c lex.yy.c -ll

lex.yy.c: yapl.l
	lex yapl.l

y.tab.c: yapl.y
	bison -v -y -d yapl.y

clean:
	rm -f lex.yy.c y.tab.c y.tab.h y.output yapl4 a.out parsing_table.txt

test-valid:
	@echo "=== VALID TESTS ===" && for f in tests/valid/*.yapl; do \
		result=$$(./yapl4 "$$f" 2>&1 | head -1); \
		echo "$$(basename $$f): $$result"; \
	done

test-errors:
	@echo "=== ERROR TESTS ===" && for f in tests/errors/*.yapl; do \
		result=$$(./yapl4 "$$f" 2>&1 | head -1); \
		echo "$$(basename $$f): $$result"; \
	done

test: test-valid test-errors