FROM julia:1.12.5-trixie

WORKDIR /app

COPY . /app

RUN julia --project=. bootstrap.jl
RUN julia --project=. precompile_app.jl

ENV CMS_SKIP_PKG_SETUP=1
ENV HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

CMD ["julia", "--project=.", "app.jl"]
