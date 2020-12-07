#include <iostream>
#include <vector>

std::vector<int> combine_vectors(std::vector<int>, std::vector<int>);

int main() {

	// Variables
	std::vector<int> first_vector, second_vector, combined_vector; // vektor el. tipa int
	int number, sum = 0;

	// Input
	std::cout << "Unesite proizvoljne cijele brojeve odvojene razmakom (nula prekida unos): ";
	while (std::cin >> number, number != 0) { // unos traje do nule ili slova
		first_vector.push_back(number); // dodavanje novog broja u vector
		sum += number; // zbrajanje sume za prosijecnu vrij
	}

	if (first_vector.size() == 0) {
		std::cout << "Unijeli ste prazan vektor" << std::endl;
		return 1;
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
	combined_vector = combine_vectors(first_vector, second_vector); // funkcija koja spaja dva vektora i vraca taj spojen vector

	for (int i = 0, length = combined_vector.size(); i < length; i++)
		std::cout << combined_vector.at(i) << ", ";

}

std::vector<int>  combine_vectors(std::vector<int> fptr, std::vector<int> sptr) { // funkcija koja spaja vectore i vraca spojen

	const int FLENGTH = fptr.size();
	const int SLENGTH = sptr.size();
	std::vector<int> combined_vector;

	for (int i = 0; i < FLENGTH; i++)
		combined_vector.push_back(fptr.at(i)); // prolazi kroz prvi vector i dodaje novom vectoru sve elemente prvog
	for (int i = 0, j = 1; i < SLENGTH; i++, j+=2) { // prolazi kroz drugi vector i dodaje izmedju svakog elementa vec nove
		if (i == FLENGTH - 1) { // u slucaju da je prvi vector kraci, prekida na vrijeme i nastavlja dalje samo da dodaje na kraj normalno
			for (int k = i; k < SLENGTH; k++)
				combined_vector.push_back(sptr.at(k));
				break;
		}
		combined_vector.insert(combined_vector.begin() + j, sptr.at(i)); // komanda da dodaje izmedju svaka dva iz prvog vectora
	}

	return combined_vector; // funkcija vraca kad je pozovemo u main novi vector

}
