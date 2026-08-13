.PHONY: run app open clean

run:
	swift run

app:
	./Scripts/make-app.sh

open: app
	open usagent.app

clean:
	rm -rf .build usagent.app
