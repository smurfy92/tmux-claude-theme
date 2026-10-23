Deux déclencheurs concurrents (cycle de 5 s et push des hooks) peuvent lancer cc-states.sh en parallèle ; le résultat reste cohérent car chaque passe réécrit tout, mais le travail est fait en double.
