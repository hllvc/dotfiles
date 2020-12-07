#include <vector>
#include <iostream>

#include "Roster.h"

using namespace std;

Roster::Roster(){
}

void Roster::addPerson(){

    string name, lastname, department, degree, email;
    int age;
    long long jmbg;
    Person person1;

cout<<"Unesite ime radnika: ";
    getline(cin,name);

cout<<"\nUnesite prezime radnika: ";
    getline(cin,lastname);


cout<<"\nUnesite jmbg radnika (13 brojeva) : ";

    cin>>jmbg;
    /*while (jmbg <1000000000000 && jmbg > 9999999999999) {

        cout << "Unesite ponovo jmbg od 13 cifri"<< endl;
        cin >> jmbg;
    };*/

cout<<"\nUnesite broj godina radnika: ";
    cin >> age;
    cin.ignore (std::numeric_limits<std::streamsize>::max(), '\n');

cout<<"\nUnesite poziciju radnika: ";
     getline(cin,department);

cout<<"\nUnesite stepen obrazovanja radnika: ";
    getline(cin,degree);

cout<<"\nUnesite email od radnika: ";
    getline(cin,email);

        person1.setName(name);
        person1.setLastName(lastname);
        person1.setJMBG(jmbg);
        person1.setAge(age);
        person1.setDepartment(department);
        person1.setDegree(degree);
        person1.setEmail(email);
employees.push_back(person1);

}

void Roster::updatePerson () {



}

void Roster::reportList() {

	for(auto i = 0; i < employees.size(); i++){
		cout << employees.at(i);

		 }
}


