wget https://github.com/mosoriob/potree/releases/download/test-v0.0.4/potree-dist.tar.gz && \
    tar -xzf potree-dist.tar.gz
mkdir -p src/ckanext-potree/ckanext/potree/public/potree/build
cp -r potree src/ckanext-potree/ckanext/potree/public/potree/build/potree
cp -r libs   src/ckanext-potree/ckanext/potree/public/potree
