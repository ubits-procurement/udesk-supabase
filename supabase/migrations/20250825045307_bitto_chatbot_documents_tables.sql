-- Enable the pgvector extension to work with embedding vectors
create extension vector;

-- Create a table to store your documents
create table bitto_ai_documents (
  id bigserial primary key,
  content text, -- corresponds to Document.pageContent
  metadata jsonb, -- corresponds to Document.metadata
  embedding vector(1536) -- 1536 works for OpenAI embeddings, change if needed
);

-- Create a function to search for documents
create function bitto_ai_match_documents (
  query_embedding vector(1536),
  match_count int default null,
  filter jsonb DEFAULT '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (bitto_ai_documents.embedding <=> query_embedding) as similarity
  from bitto_ai_documents
  where metadata @> filter
  order by bitto_ai_documents.embedding <=> query_embedding
  limit match_count;
end;
$$;
