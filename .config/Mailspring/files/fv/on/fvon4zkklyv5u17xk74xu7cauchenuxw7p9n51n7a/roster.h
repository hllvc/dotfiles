#ifndef MENU_H
#define MENU_H

#include "Person.h"

#include <string>
#include <iostream>
#include <vector>

using namespace std;

class Roster
{
    public:

        Roster();
        void addPerson(), updatePerson(), searchPerson(), reportList(), deletePerson();

    private:
				vector<Person> employees;


};

#endif // MENU_H
