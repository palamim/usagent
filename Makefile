.PHONY: run app open update clean

run:
	swift run

app:
	./Scripts/make-app.sh

open: app
	open usagent.app

update:
	./Scripts/update.sh

clean:
	rm -rf .build usagent.app
