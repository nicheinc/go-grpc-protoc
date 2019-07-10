FROM alpine:3.8 as protoc_builder
RUN apk add --no-cache build-base curl automake autoconf libtool git zlib-dev go

ENV PROTOBUF_VERSION=3.8.0 \
	GO_PROTOBUF_VERSION=1.3.1 \
	GRPC_VERSION=1.21.0 \
	GRPC_GATEWAY_VERSION=1.9.3 \
	PROTOC_GEN_DOC_VERSION=f824a8908ce33f213b2dba1bf7be83384c5c51e8 \
	PROTOC_GEN_VALIDATE_VERSION=f718d61a7304340d508536353c02941a335b18e7

ENV OUTDIR=/out


RUN mkdir -p /protobuf && \
	curl -L https://github.com/google/protobuf/archive/v${PROTOBUF_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf

RUN git clone --depth 1 --recursive -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc && \
        rm -rf grpc/third_party/protobuf && \
        ln -s /protobuf /grpc/third_party/protobuf

RUN cd /protobuf && \
        autoreconf -f -i -Wall,no-obsolete && \
        ./configure --prefix=/usr --enable-static=no && \
        make -j2 && make install

RUN cd grpc && \
        make -j2 plugins

RUN cd /protobuf && \
        make install DESTDIR=${OUTDIR}

RUN cd /grpc && \
        make install-plugins prefix=${OUTDIR}/usr

RUN find ${OUTDIR} -name "*.a" -delete -or -name "*.la" -delete

ENV GOPATH=/go \
        PATH=/go/bin/:$PATH

RUN mkdir -p ${GOPATH}/src/github.com/golang && cd ${GOPATH}/src/github.com/golang && git clone https://github.com/golang/protobuf && cd protobuf && git checkout tags/v${GO_PROTOBUF_VERSION} && go get ./... && go install ./...
RUN mkdir -p ${GOPATH}/src/github.com/grpc-ecosystem && cd ${GOPATH}/src/github.com/grpc-ecosystem && git clone https://github.com/grpc-ecosystem/grpc-gateway && cd grpc-gateway && git checkout tags/v${GRPC_GATEWAY_VERSION} && go get ./... && go install ./protoc-gen-swagger && go install ./protoc-gen-grpc-gateway
RUN mkdir -p ${GOPATH}/src/github.com/envoyproxy && cd ${GOPATH}/src/github.com/envoyproxy && git clone https://github.com/envoyproxy/protoc-gen-validate && cd protoc-gen-validate && git checkout ${PROTOC_GEN_VALIDATE_VERSION} && make build
RUN mkdir -p ${GOPATH}/src/github.com/pseudomuto && cd ${GOPATH}/src/github.com/pseudomuto && git clone https://github.com/pseudomuto/protoc-gen-doc && cd protoc-gen-doc && git checkout ${PROTOC_GEN_DOC_VERSION} && go get ./... && go install ./...
RUN install -c ${GOPATH}/bin/protoc-gen* ${OUTDIR}/usr/bin/

FROM znly/upx as packer
COPY --from=protoc_builder /out/ /out/
RUN upx --lzma \
        /out/usr/bin/protoc \
        /out/usr/bin/grpc_* \
        /out/usr/bin/protoc-gen-*

FROM alpine:3.7
ENV GOPATH=/go
RUN apk add --no-cache libstdc++ jq sed
COPY --from=packer /out/ /

COPY --from=protoc_builder /protobuf/ /protobuf/google/protobuf/
COPY --from=protoc_builder ${GOPATH}/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis/google/api/ /protobuf/google/api/
COPY --from=protoc_builder ${GOPATH}/src/github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger/ /protobuf/protoc-gen-swagger/
COPY --from=protoc_builder ${GOPATH}/src/github.com/envoyproxy/protoc-gen-validate/validate/ /protobuf/validate/

RUN chmod a+x /usr/bin/protoc

ENTRYPOINT ["/usr/bin/protoc", "-I/protobuf"]
