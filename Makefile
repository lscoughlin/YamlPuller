# YamlPuller - Free Pascal YAML 1.2 pull parser
#
#   make          build the library units
#   make test     build + run the fpcunit suite
#   make clean    remove build outputs

FPC       ?= fpc
UNITS     ?= /usr/local/lib/fpc/3.2.4/units/aarch64-darwin
FPCFLAGS  ?= -Mdelphi -vw -Fu./src \
             -Fu$(UNITS)/fcl-fpcunit -Fu$(UNITS)/fcl-json -Fu$(UNITS)/fcl-base \
             -Fu$(UNITS)/rtl -Fu$(UNITS)/rtl-objpas -Fu$(UNITS)/rtl-extra
BIN        = bin

EXAMPLES   = example_string example_bytes example_stream example_file example_events example_section

.PHONY: all test examples clean

all:
	@mkdir -p $(BIN)
	$(FPC) $(FPCFLAGS) -Cn -FE$(BIN) -FU$(BIN) src/YamlPuller.pas

examples: all
	@mkdir -p $(BIN)
	@for ex in $(EXAMPLES); do \
	  $(FPC) $(FPCFLAGS) -FE$(BIN) -FU$(BIN) examples/$$ex.pas >/dev/null || exit 1; \
	done
	@for ex in $(EXAMPLES); do \
	  $(BIN)/$$ex >/dev/null || exit 1; \
	done
	@echo "examples: PASS"

test: all
	$(FPC) $(FPCFLAGS) -Fu./test -FE$(BIN) -FU$(BIN) test/YamlPuller.RunTests.pas
	$(BIN)/YamlPuller.RunTests --all --format=plain --sparse

clean:
	rm -rf $(BIN) src/*.o src/*.ppu test/*.o test/*.ppu
