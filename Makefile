.PHONY: setup run folder

setup:
	python3 -m venv venv
	. venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt

run:
	. venv/bin/activate && python3 heatmap.py
 
# Allow 'make FOLDER=/path/to/folder' to work without specifying a target
.DEFAULT_GOAL := folder

folder:
	. venv/bin/activate && python3 heatmap.py --folder $(FOLDER)
