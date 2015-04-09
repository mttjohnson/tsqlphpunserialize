IF OBJECT_ID (N'dbo.fnParsePhpSerializedString') IS NOT NULL
   DROP FUNCTION dbo.fnParsePhpSerializedString
GO
CREATE FUNCTION dbo.fnParsePhpSerializedString( @phpSerialized VARCHAR(MAX))
RETURNS @results table 
	(
		element_id int identity(1,1) not null, /* internal surrogate primary key gives the order of parsing and the list order */
		parent_id int, /* if the element has a parent then it is in this column. */
		var_name varchar(50), /* the name or key of the element in a key/value array list */
		var_type varchar(50),
		var_length int,
		value_int int,
		value_string varchar(max),
		value_decimal decimal(38,17)
	)
AS
BEGIN

	/*
    Built by Matt Johnson (matt@evdat.com) 2012-08-14
	Bug Fixes by Matt Johnson (matt@evdat.com) 2012-11-27
	*/

	-- we use this table later for collecting auto generated
	-- identity values when inserting records into @results
	declare @insertedIds table (
		element_id int
	)

	-- define variables
	declare @element_start int
	declare @var_type_end int
	declare @var_type varchar(50)
	declare @element_end int
	declare @chunk varchar(max)
	declare @var_length_start int
	declare @var_length_end int
	declare @var_length_string varchar(max)
	declare @var_length int
	declare @value_start int
	declare @value_end int
	declare @value_string varchar(max)
	declare @value_int int
	declare @value_decimal decimal(38,17)
	declare @array_level int
	declare @value_string_position int
	declare @next_open int
	declare @next_close int
	declare @parent_id int
	declare @element_id int
	declare @key_element_id int
	declare @inserted_element_id int
	declare @var_name varchar(50)
	declare @found_null int
	declare @quote_start int
	declare	@quote_end int

	--initialize variables
	set @parent_id = 0


	--loop through the supplied @phpSerialized string until it's empty
	while 1=1 begin
		set @element_start = null
		set @var_type_end = null
		set @var_type = null
		set @element_end = null
		set @chunk = null
		set @var_length_start = null
		set @var_length_end = null
		set @var_length_string = null
		set @var_length = null
		set @value_start = null
		set @value_end = null
		set @value_string = null
		set @value_int = null
		set @value_decimal = null
		set @array_level = null
		set @value_string_position = null
		set @next_open = null
		set @next_close = null
		set @var_name = null
		set @found_null = null
		set @quote_start = null
		set @quote_end = null

		---- remove comments below for debugging purposes outside of function
		--print '------------------------------------------------'
		--print '@phpSerialized: ' + coalesce(cast(@phpSerialized as varchar(max)),'') 

		--identify if the element is a null element
		set @found_null = patindex('N;%', @phpSerialized)

		--confirm that there is an element to parse and define its starting point
		--patindex will return a value of 1 if the pattern is found and this pattern
		--will only match if the element starting point is the first character in the
		--supplied string. If it is encapsulated in quotes or anything else it will not match
		set @element_start = patindex('[Nasidb]%[;}]', @phpSerialized)

		if @element_start <= 0 begin
			--if the supplied string is now empty check the existing results table
			--for any nested elements in any array elements

			--reset the value of @element_id to be safe
			set @element_id = null

			--only retrieve the first element found containing sub elements to parse
			select	top 1 
					@phpSerialized = value_string,
					@element_id = element_id	
			from @results 
			where	var_type = 'a' and 
					value_string is not null
			
			--set the parent_id to the array's element_id
			set @parent_id = @element_id

			--if there were no results found then that means there either
			--were no arrays to parse, or all arrays have already been parsed
			--so break the continuous loop because we are completely done now
			if @element_id is null break
			
			--set the @element_start again now that we 
			--have a new string to parse for elements
			set @element_start = patindex('[Nasidb]%[;}]', @phpSerialized)

			---- remove comments below for debugging purposes outside of function
			--print '-----nested elements in an array element'
			--print '@phpSerialized: ' + coalesce(cast(@phpSerialized as varchar(max)),'') 
		end

		--null and string elements have a different structure then other elements, they have not value
		if @found_null > 0 begin
			--find the end of the type of the element then extract the variable type from the string
			set @var_type_end = patindex('%;%', @phpSerialized)
			set @var_type = substring(@phpSerialized, @element_start, @var_type_end-@element_start)
		end else begin
			--find the end of the type of the element then extract the variable type from the string
			set @var_type_end = patindex('%:%', @phpSerialized)
			set @var_type = substring(@phpSerialized, @element_start, @var_type_end-@element_start)
		end


		--array elements contain sub elements so we use different methods for parsing
		--sub elements than we do for parsing individual elements.
		if @var_type = 'N' begin
			-- null value

			-- set all values to null
			set @var_length = null
			set @value_string = null
			set @value_int = null
			set @value_decimal = null

			set @element_end = patindex('%;%', @phpSerialized)+1
			set @chunk = substring(@phpSerialized, @element_start, @element_end-@element_start)

		end else if @var_type like '[sidb]' begin
			--element has no sub elements

			--determine the end of this individual element and then extract 
			--only this individual element from the string
			if @var_type = 's' begin
				--find the start of the string quotes
				set @quote_start = patindex('%"%";%', @phpSerialized)

				--find the end of the string quotes
				set @quote_end = patindex('%";%', @phpSerialized)
				
				set @element_end = patindex('%;%', substring(@phpSerialized, @quote_end, len(@phpSerialized))) + @quote_end
			end else begin
				set @element_end = patindex('%;%', @phpSerialized)+1
			end
			set @chunk = substring(@phpSerialized, @element_start, @element_end-@element_start)
			
			--strings are serialized differently than numeric elements
			if @var_type = 's' begin
				--element has var length

				--find the starting and ending positions for the var_length and then extract the length
				set @var_length_start = @var_type_end+1
				set @var_length_end = patindex('%:%', substring(@chunk, @var_length_start, len(@chunk))) + @var_length_start - 1
				set @var_length_string = substring(@chunk, @var_length_start, @var_length_end-@var_length_start)
				if @var_length_string not like '[^0-9]' begin
					--its nice to verify this is actually a number before casting it as such
					set @var_length = cast(@var_length_string as int)
				end

				--if the specified var length is longer than the detected ending quote use it to 
				--re-determine the element end and chunk contents this can happen if quotes are
				--included in the string contents
				if @var_length > @quote_end begin
					set @element_end = patindex('%;%', substring(@phpSerialized, @var_length_end+@var_length+2, len(@phpSerialized))) + @var_length_end+@var_length+2
					set @chunk = substring(@phpSerialized, @element_start, @element_end-@element_start)
				end

				--find the starting and ending positions for the value and then extract the value
				set @value_start = @var_length_end+1
				set @value_end = @element_end - 1
				--a string value is quoted so remove quotes in start and end of substring for value
				--we set the substring starting position +1 just past the start of the quote and then
				--set the length of the extracted string -2 to account for both the starting quote and 
				--ending quote to be removed from the extracted string.
				set @value_string = substring(@chunk, @value_start+1, @value_end-@value_start-2)
				
			end else begin
				--element does not have a var length

				--find the starting and ending positions for the value and then extract the value as a string
				set @value_start = @var_type_end+1
				set @value_end = patindex('%;%', @chunk)
				set @value_string = substring(@chunk, @value_start, @value_end-@value_start)

				--determine what value type the string should be converted to
				if @var_type = 'i' begin
					if @value_string not like '[^0-9.]' begin
						set @value_int = cast(@value_string as int)
						--clear the value_string because the element's value has been converted to its appropriate type
						set @value_string = null
					end
				end else if @var_type = 'd' begin
					-- d actually stands for double not decimal... incase this causes errors later...
					if @value_string not like '[^0-9.]' begin
						--set @value_decimal = cast(@value_string as float)
						set @value_decimal = cast(round(@value_string,17) as decimal(38,17)) 
						--clear the value_string because the element's value has been converted to its appropriate type
						set @value_string = null
					end
				end else if @var_type = 'b' begin
					if @value_string not like '[^0-1]' begin
						set @value_int = cast(@value_string as int)
						--clear the value_string because the element's value has been converted to its appropriate type
						set @value_string = null
					end
				end

			end
			
			
		end else if @var_type = 'a' begin
			--element is array and has sub elements

			--we are going to chop up the string to try and determine its end so we'll
			--first set the string to a variable we can destroy in this process
			set @chunk = @phpSerialized

			--find the starting and ending positions for the var_length and then extract the length
			--arrays use this to state how may elements this array contains
			set @var_length_start = @var_type_end+1
			set @var_length_end = patindex('%:%', substring(@chunk, @var_length_start, len(@chunk))) + @var_length_start - 1
			set @var_length_string = substring(@chunk, @var_length_start, @var_length_end-@var_length_start)
			if @var_length_string not like '[^0-9]' begin
				set @var_length = cast(@var_length_string as int)
			end

			--find the value starting position
			--later we will find the true end of the value
			set @value_start = @var_length_end+1

			-- to determine the ending position we have to dig through the sub elements and track the
			-- nested level to identify the ending brace for this level
			set @array_level = 0
			--we start the string position at 1 for the begining of the serialized string
			set @value_string_position = 1

			-- loop through the value chopping up the chunk while trying to find the ending brace for this array
			while 1=1 begin

				--find the next open and close braces in the chunk
				set @next_open = patindex('%{%', @chunk)
				set @next_close = patindex('%}%', @chunk)
				
				--check to see which brace is the next in the chunk
				if @next_open > 0 and @next_open < @next_close begin
					--found an opening brace
					
					--since this is an opening brace we need to increment the level and strip off
					--everything from the chunk before the brace so that we can search for additional braces
					--we also note the position in the string for use in finding the end of the value later
					--we track the previous position and add to it because we keep chopping off the beginning of
					--the chunk as we parse through the string, and later we will need to reference the position
					--relative to the entire serialized string.
					set @value_string_position = @value_string_position + patindex('%{%', @chunk)-1
					set @chunk = substring(@chunk, patindex('%{%', @chunk)+1, len(@chunk))
					set @array_level = @array_level + 1

				end else if @next_close > 0 begin
					--found a closing brace
					--print 'found close at level: ' + cast(@array_level as varchar(10)) + '(' + cast(patindex('%}%', @chunk) as varchar(10)) + ')'
					
					--since this is a closing brace we need to decrement the level and strip off
					--everything from the chunk before the brace so that we can search for additional braces
					--we also note the position in the string for use in finding the end of the value later
					--we track the previous position and add to it because we keep chopping off the beginning of
					--the chunk as we parse through the string, and later we will need to reference the position
					--relative to the entire serialized string.
					set @value_string_position = @value_string_position + patindex('%}%', @chunk)+1
					set @chunk = substring(@chunk, patindex('%}%', @chunk)+1, len(@chunk))
					set @array_level = @array_level - 1

				end else break

				--once we get back to level 0 we know we've found the end of this array element
				--so break the continuous loop now that we have the ending position
				if @array_level <= 0 break
			end

			--set the ending position of the element and the value since the value is the last part of the element
			set @element_end = @value_string_position
			set @value_end = @element_end
			--an array value is surrounded by braces so remove the braces in start and end of the substring value
			--we set the substring starting position +1 just past the start of the opening brace and then
			--set the length of the extracted string -2 to account for both the opening brace and 
			--closing brace to be removed from the extracted string.
			set @value_string = substring(@phpSerialized, @value_start+1, @value_end-@value_start-2)
			set @chunk = substring(@phpSerialized, @element_start, @element_end-@element_start)
			
			-- if the array is empty just set it to null so that
			-- we don't try and parse the contents of the array value later.
			if @value_string = '' set @value_string = null
		end else begin
			-- unkown type...
			set @var_type = null

			-- at least grab the end of the element and set the chunk for the element contents
			set @element_end = patindex('%;%', @phpSerialized)+1
			set @chunk = substring(@phpSerialized, @element_start, @element_end-@element_start)

			-- at least list the contents of the element in the value_string of an undefined record
			set @var_length = null
			set @value_string = @chunk
			set @value_int = null
			set @value_decimal = null
		end




		--we populate the results table differently depending on the element that is being parsed. 
		--Any element contained in an array has a key element and a value element. Though we parse
		--all key elements in an array all we do with them in the results table is set their value
		--as the var_name (key) for the element, and store the key_element_id for setting the value
		--in the next pass since key/value pairs are listed sequentially in a serialized string.
		if @parent_id > 0 and @key_element_id > 0 begin
			--parent_id > 0 indicates this is a sub element inside an array
			--and the array contents currently being parsed contain key elements and value
			--elements sequentially in the serialized string. Because key_element_id is not 0
			--we know this must be the value part of the element contained in the array as the
			--key was just previously defined.

			--update the existing keyed element with it's type, length and value
			update @results
			set var_type = @var_type, 
				var_length = @var_length, 
				value_string = @value_string, 
				value_int = @value_int, 
				value_decimal = @value_decimal
			where element_id = @key_element_id		
			
			set @key_element_id = null
		end else if @parent_id > 0 and @var_type like '[sid]' begin
			--this element is a part of the array which contains key/value paris and since
			--the @key_element_id is 0 or not defined we can asume this is the key of the pair
			
			--determine what the key element type is and cast it as a string to the var_name
			if @var_type = 's' set @var_name = @value_string
			if @var_type = 'i' set @var_name = cast(@value_int as varchar(50))
			if @var_type = 'd' set @var_name = cast(@value_decimal as varchar(50))

			--insert a new record into the results table defining the parent_id and var_name
			insert @results 
			(
				parent_id,
				var_name
			) 
			output inserted.element_id into @insertedIds 
			values (
				@parent_id,
				@var_name
			)

			--since we stored the identity value in the output set that value to @inserted_element_id
			select top 1 @inserted_element_id = element_id from @insertedIds
			delete from @insertedIds

			--set the key_element_id so that the next pass catches the value and assigns it to this result record
			set @key_element_id = @inserted_element_id

		end else begin
			--this will be executed for parsed strings that are not part of an array
			--in which case the elements do not contain value_name keys

			--also any unkown types will fall down into this statement and get a record inserted
			
			--insert the entire element details into the results table
			insert into @results 
			(
				parent_id, 
				var_type, 
				var_length, 
				value_string, 
				value_int, 
				value_decimal
			) 
			output inserted.element_id into @insertedIds 
			values (
				@parent_id,
				@var_type,
				@var_length,
				@value_string,
				@value_int,
				@value_decimal
			)

			--here we capture the identiy value for the inserted record
			select top 1 @inserted_element_id = element_id from @insertedIds
			delete from @insertedIds
		end

		-- if the current php serilized string was an array then it would have
		-- been parsed and elements added to the results, so we should remove
		-- the value_string from the array element in the results table so that
		-- it doesn't get parsed again in the loop. 
		if @element_id is not null begin
			--the only strings that get parsed where the @element_id has
			--a value is from an array element
			update @results
			set value_string = null
			where element_id = @element_id
		end

		--since we have parsed this element from the serialized string chop off this element
		--from the string and run the rest of it through the loop again to ensure all
		--elements have been parsed from the supplied serialized string.
		set @phpSerialized = substring(@phpSerialized, @element_end, len(@phpSerialized))

		---- remove comments below for debugging purposes outside of function
		--print '@inserted_element_id: ' + coalesce(cast(@inserted_element_id as varchar(max)),'')
		--print '@parent_id: ' + coalesce(cast(@parent_id as varchar(max)),'')
		--print '@var_type: ' + coalesce(cast(@var_type as varchar(max)),'')
		--print '@var_length: ' + coalesce(cast(@var_length as varchar(max)),'')
		--print '@value_string: ' + coalesce(cast(@value_string as varchar(max)),'')
		--print '@value_int: ' + coalesce(cast(@value_int as varchar(max)),'')
		--print '@value_decimal: ' + coalesce(cast(@value_decimal as varchar(max)),'')

		--print ''
		--print '@found_null: ' + coalesce(cast(@found_null as varchar(max)),'')
		--print '@element_start: ' + coalesce(cast(@element_start as varchar(max)),'')
		--print '@var_type_end: ' + coalesce(cast(@var_type_end as varchar(max)),'')
		--print '@element_end: ' + coalesce(cast(@element_end as varchar(max)),'')
		--print '@chunk: ' + coalesce(cast(@chunk as varchar(max)),'')
		--print '@var_length_start: ' + coalesce(cast(@var_length_start as varchar(max)),'')
		--print '@var_length_end: ' + coalesce(cast(@var_length_end as varchar(max)),'')
		--print '@var_length_string: ' + coalesce(cast(@var_length_string as varchar(max)),'')
		--print '@value_start: ' + coalesce(cast(@value_start as varchar(max)),'')
		--print '@value_end: ' + coalesce(cast(@value_end as varchar(max)),'')
		--print '@array_level: ' + coalesce(cast(@array_level as varchar(max)),'')
		--print '@value_string_position: ' + coalesce(cast(@value_string_position as varchar(max)),'')
		--print '@next_open: ' + coalesce(cast(@next_open as varchar(max)),'')
		--print '@next_close: ' + coalesce(cast(@next_close as varchar(max)),'')
		--print '@quote_start: ' + coalesce(cast(@quote_start as varchar(max)),'')
		--print '@quote_end: ' + coalesce(cast(@quote_end as varchar(max)),'')

	end

	return
end
