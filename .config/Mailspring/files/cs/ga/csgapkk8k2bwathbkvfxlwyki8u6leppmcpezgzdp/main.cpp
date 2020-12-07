#include <iostream>
#include "Person.h"
#include "Roster.h"
#include <string>
#include <vector>

using namespace std;

int main() {

	Roster roster;

	roster.addPerson();
    system("CLS");
	roster.reportList();


}
