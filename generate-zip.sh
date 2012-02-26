set -x
cd ..
zip -r Hype\ Machine Hype\ Machine -x \*.zip \*.sh \*.git\* \*README\* \*webauth\*
mv Hype\ Machine.zip Hype\ Machine
cd Hype\ Machine

VERSION=$(grep \<version\> install.xml  | perl -n -e '/>(.*)</; print $1;')
SHA=$(shasum HypeM.zip | awk '{print $1;}')

cat <<EOF > public.xml
<extensions>
<details>
<title lang="EN">Whizziwig's Plugins</title>
</details>
<plugins>
<plugin name="Hype Machine" version="$VERSION" minTarget="7.5" maxTarget="*">
<title lang="EN">Hype Machine</title>
<desc lang="EN">Browse, search and play urls from soundcloud</desc>
<url>http://whizziwig.com/static/hypebox/HypeM.zip</url>
<link>https://github.com/blackmad/Hype-Machine-Squeezebox-Plugin</link>
<sha>$SHA</sha>
<creator>David Blackman</creator>
<email>david+hypebox@whizziwig.com</email>
</plugin>
</plugins>
</extensions>
EOF

