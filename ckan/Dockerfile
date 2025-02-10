FROM ckan/ckan-base:2.9-py3.9
# Install any extensions needed by your CKAN instance
# See Dockerfile.dev for more details and examples

USER root
RUN apt-get install -y python3-dev libxml2-dev libxslt1-dev libgeos-c1v5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN chown -R ckan: /srv/app

RUN groupmod -g 826671 ckan-sys && echo "Modified group ID for ckan-sys to 826671"

RUN find /var/lib/ckan -gid 502 ! -type l -exec chgrp 826671 {} \;
RUN find ${APP_DIR} -gid 502 ! -type l -exec chgrp 826671 {} \;
RUN find /docker-entrypoint.d -gid 502 ! -type l -exec chgrp 826671 {} \;
RUN find /usr/local -gid 502 ! -type l -exec chgrp 826671 {} \;
RUN find ${CKAN_STORAGE_PATH} -gid 502 ! -type l -exec chgrp 826671 {} \;
RUN find /srv/app -gid 502 ! -type l -exec chgrp 826671 {} \;

USER ckan

RUN pip install ckanext-geoview
ADD requirements/ckanext-spatial.txt /tmp/
RUN pip3 install -r /tmp/ckanext-spatial.txt
RUN pip3 install -e "git+https://github.com/ckan/ckanext-spatial.git#egg=ckanext-spatial"
RUN pip3 install -e 'git+https://github.com/mosoriob/ckanext-oauth2.git@0.8.1#egg=ckanext-oauth2'
RUN pip3 install -e 'git+https://github.com/mosoriob/ckanext-tacc_theme.git@ec95b45a99c9ceb487b8386cc72d6a74da9f2fda#egg=ckanext-tacc_theme'

# Copy custom initialization scripts
COPY docker-entrypoint.d/* /docker-entrypoint.d/

# Apply any patches needed to CKAN core or any of the built extensions (not the
# runtime mounted ones)
COPY patches ${APP_DIR}/patches

RUN for d in $APP_DIR/patches/*; do \
    if [ -d $d ]; then \
    for f in `ls $d/*.patch | sort -g`; do \
    cd $SRC_DIR/`basename "$d"` && echo "$0: Applying patch $f to $SRC_DIR/`basename $d`"; patch -p1 < "$f" ; \
    done ; \
    fi ; \
done