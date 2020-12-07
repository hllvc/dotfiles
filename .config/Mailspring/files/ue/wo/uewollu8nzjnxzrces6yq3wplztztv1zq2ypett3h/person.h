#ifndef PERSON_H
#define PERSON_H

#include <iostream>
#include <string>

using namespace std;

class Person
{
   public:

        Person();
				Person(string firstName, string lastName, long long jmbg, int age, string department, string degree,string email);

        void setName(string), setLastName(string), setAge(int), setJMBG(long long), setEmail(string), setDegree(string), setDepartment(string);

        string getName (), getLastName(), getEmail(), getDegree(), getDepartment();
        int getAge();
				long long getJMBG();

				friend ostream& operator<<(ostream& os, const Person& employee); // ne diraj, RADI!!!
    private:

        string firstName, lastName, degree, email, department;
        int age;
				long long jmbg;


};

#endif // PERSON_H
