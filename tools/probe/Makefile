TOOLS = raw dumpr scan wq opmode
all: $(addprefix build/,$(TOOLS))
build/%: %.c
	mkdir -p build
	clang -O2 -w -o $@ $< -framework IOKit -framework CoreFoundation
clean:
	rm -rf build
.PHONY: all clean
