#include "Person.h"
#include <iostream>
#include <string>

using namespace std;

Person::Person(){
}

Person::Person(string firstName, string lastName, long long jmbg, int age, string department, string degree,string email) {

	this->firstName = firstName;
	this->lastName = lastName;
	this->jmbg = jmbg;
	this->age = age;
	this->department = department;
	this->degree = degree;
	this->email = email;
}

void Person::setName (string firstName) {

        this->firstName = firstName;
}

string Person::getName (){
    return this->firstName;
}

void Person::setLastName(string lastName){

    this->lastName = lastName;
}

string Person::getLastName(){

    return this->lastName;

}

void Person::setJMBG (long long jmbg){
    this->jmbg = jmbg;
}

long long Person::getJMBG(){
    return this->jmbg;
}

void Person::setAge(int age){
    this->age = age;
}

int Person::getAge(){
    return this->age;
}

void Person::setEmail(string email){
    this->email = email;
}

string Person::getEmail(){
    return this->email;
}

void Person::setDegree(string degree) {
    this->degree = degree;
}

string Person::getDegree(){
    return this->degree;
}

void Person::setDepartment(string departemnt){
    this->department = departemnt;
}

string Person::getDepartment(){
    return department;
}


    ostream& operator<<(ostream& os, const Person& employee) {

        os << employee.firstName << "\t" << employee.lastName<<"\t"<< employee.jmbg <<"\t" <<employee.age<<"\t"<<employee.department <<"\t"<<employee.degree<<"\t"<<employee.email<< "\n";
        return os;
        // NE DIRAJ, RADI!!! by: EMSAR.
};



