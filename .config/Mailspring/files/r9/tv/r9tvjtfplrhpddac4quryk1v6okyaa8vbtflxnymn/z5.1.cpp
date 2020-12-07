#include <iostream>
#include <vector>

void combine_vectors(std::vector<int>, std::vector<int>);

int main() {

	// Variables
	std::vector<int> first_vector, second_vector; // vektor el. tipa int
	int number, sum = 0;

	// Input
	std::cout << "Unesite proizvoljne cijele brojeve odvojene razmakom (nula prekida unos): ";
	while (std::cin >> number, number != 0) { // unos traje do nule ili slova
		first_vector.push_back(number); // dodavanje novog broja u vector
		sum += number; // zbrajanje sume za prosijecnu vrij
	}

	for (int i = 0, length = first_vector.size(); i < length; i++) { // petlja krece od nule tjst. prelazi redom niz
		int temp; // pomocna varijable
		for (int j = i+1; j < length; j++) { // druga petlja koja krece za jedno mjesto iznad
			if (first_vector.at(i) > first_vector.at(j)) { // poredi npr prvi element i drugi, drugi i treci, treci i cetvrti itd.
				temp = first_vector.at(i); // u slucaju da vrijdi uslov u if
				first_vector.at(i) = first_vector.at(j); // nastavlja sve ovo
				first_vector.at(j) = temp; // tako da zamijeni mjesta 
			}
		}
	}

	std::cout << "Sortiran niz izgleda: ";
	for (int i = 0, length = first_vector.size(); i < length; i++)
		std::cout << first_vector.at(i) << ", "; // petlja koja printa sve elemente prvog vectora
	std::cout << std::endl;

	std::cout << "Najmanji clan vectora je " << first_vector.at(0) << ", a najveci " << first_vector.at(first_vector.size()-1) << std::endl; // ispisuje najveci i najmanji clan

	std::cout << "Prosijecna vrijednost vectora je " << (double)sum/first_vector.size() << std::endl; // ipisuje prosijecnu vrijednost

	std::cout << "Unesite novi vecotor: ";
	while (std::cin >> number, number != 0) // unos drugog vectora
		second_vector.push_back(number);

	std::cout << "Kombinacija ova dva vektora je: ";
	combine_vectors(first_vector, second_vector); // funkcija koja spaja i printa spojen vector

}

void combine_vectors(std::vector<int> fptr, std::vector<int> sptr) { // funkcija koja spaja i printa spojen vector

	const int FLENGTH = fptr.size(); // const duzina prvog
	const int SLENGTH = sptr.size(); // const duzina drugog
	const int TEMP_SIZE = FLENGTH + SLENGTH;
	int temp[TEMP_SIZE]; // novi niz velicine oba

	for (int i = 0, j = 0; i < FLENGTH; i++, j+=2) // smijestanje prvog na svako parno mjesto uklj nulu
		temp[j] = fptr.at(i);
	for (int i = 0, j = 1; i < SLENGTH; i++, j+=2) // smjestanje drugog na neparna mjesta
		temp[j] = sptr.at(i);

	for (int i = 0, length = TEMP_SIZE; i < length; i++) // printanje novog vectora
		std::cout << temp[i] << ", ";
	std::cout << std::endl;

}
