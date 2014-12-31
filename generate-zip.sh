set -x

# recupère la version inscrite dans install.xml avant de changer de dossier
VERSION=$(grep \<version\> install.xml  | perl -n -e '/>(.*)</; print $1;')

# créer un dossier temporaire qui va contenir le zip
mkdir generateTpl
cd generateTpl
# télécharge le zip pour le hasher
wget https://github.com/timothylhuillier/Hype-Machine-Squeezebox-Plugin/archive/master.zip
# hash le zip et stock la valeur dans la variable 'SHA'
SHA=$(shasum master.zip | awk '{print $1;}')

# retour dans le dossier parent et supprime le dossier temporaire
cd ../
rm -rf generateTpl

# Mets à jour le fichier repo.xml
cat <<EOF > repo.xml
<?xml version="1.0"?>

<extensions>
	<details>
		<title lang="EN">timothylhuillier's Plugins</title>
	</details>
	<plugins>
		<plugin name="HypeM" version="$VERSION" minTarget="7.0" maxTarget="7.*">
			<title lang="EN">Hype Machine</title>
			<desc lang="EN">A plugin for the logitech meda server, HypeM is a platform of streamin music.</desc>
			<url>http://paperops.fr/lms/hypem.zip</url>
			<sha>$SHA</sha>
			<link>https://github.com/timothylhuillier/Hype-Machine-Squeezebox-Plugin</link>
			<creator>David BLACKMAN and Timothy L'HUILLIER</creator>
			<email>timothylhuillier@gmail.com</email>
		</plugin>
	</plugins>
</extensions>
EOF

