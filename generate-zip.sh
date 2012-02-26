set -x
cd ..
zip -r HypeM HypeM -x \*.zip \*.sh \*.git\* \*README\* \*webauth\*
mv HypeM.zip HypeM
cd HypeM

VERSION=$(grep \<version\> install.xml  | perl -n -e '/>(.*)</; print $1;')
SHA=$(shasum HypeM.zip | awk '{print $1;}')

cat <<EOF > public.xml
<extensions>
<details>
<title lang="EN">Whizziwig's Plugins</title>
</details>
<plugins>
<plugin name="HypeM" version="$VERSION" minTarget="7.5" maxTarget="*">
<title lang="EN">Hype Machine</title>
<desc lang="EN">Browse, search and play urls from The Hype Machine</desc>
<url>http://whizziwig.com/static/hypebox/HypeM.zip</url>
<link>https://github.com/blackmad/Hype-Machine-Squeezebox-Plugin</link>
<sha>$SHA</sha>
<creator>David Blackman</creator>
<email>david+hypebox@whizziwig.com</email>
</plugin>
</plugins>
</extensions>
EOF

