-- Add unique constraint to prevent duplicates for a given attachment
ALTER TABLE public.document_content
ADD CONSTRAINT document_content_attachment_unique UNIQUE (attachment_id);
