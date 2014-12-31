set -x

# recupère la version inscrite dans install.xml avant de changer de dossier
VERSION=$(grep \<version\> install.xml  | perl -n -e '/>(.*)</; print $1;')

# rejoins le dossier parent et créer un dossier contenant les zips
cd ../
mkdir generateZip
cd generateZip

# zip le contenu du plugin
zip -r HypeM-$VERSION.zip ../HypeM -x \*.zip \*.sh \*.git\* \*README\* \*webauth\*
# hash le zip et stock la valeur dans la variable 'SHA'
SHA=$(shasum HypeM-$VERSION.zip | awk '{print $1;}')

# retour dans le dossier du plugin
cd ../HypeM

# Mets à jour le fichier repo.xml
cat <<EOF > repo.xml
<?xml version="1.0"?>

<extensions>
	<details>
		<title lang="EN">timothylhuillier's Plugins</title>
	</details>
	<plugins>
		<plugin name="HypeM" version="$VERSION" minTarget="7.5" maxTarget="7.*">
			<title lang="EN">Hype Machine</title>
			<desc lang="EN">A plugin for the logitech meda server, HypeM is a platform of streamin music.</desc>
			<url>http://paperops.fr/lms/HypeM-$VERSION.zip</url>
			<sha>$SHA</sha>
			<link>https://github.com/timothylhuillier/Hype-Machine-Squeezebox-Plugin</link>
			<creator>David BLACKMAN and Timothy L'HUILLIER</creator>
			<email>timothylhuillier@gmail.com</email>
		</plugin>
	</plugins>
</extensions>
EOF
