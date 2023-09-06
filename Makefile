CRED=-U postgres -d retail_analystics
SRC=-f src/part1.sql -f src/part2_customers.sql \
		-f src/part2_purchase_history.sql -f src/part2_periods.sql \
		-f src/part2_groups.sql -f src/part3.sql -f src/part4.sql \
		-f src/part5.sql -f src/part6.sql

all: move create 

create:
	psql -U postgres -c 'CREATE DATABASE retail_analystics;' 
	psql $(CRED) -a $(SRC)

move:
	cp -r ./datasets /tmp/datasets
	chmod -R 777 /tmp/datasets

drop:
	psql -U postgres -c 'DROP DATABASE IF EXISTS retail_analystics;'

.PHONY: all move create drop

