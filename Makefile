# Makefile for Vision Pro Heatmap Server

.PHONY: setup run folder

setup:
	python3 -m venv venv
	. venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt

run:
	. venv/bin/activate && python3 heatmap.py
 
folder:
	. venv/bin/activate && python3 heatmap.py --folder $(FOLDER)
