__max_print_stack_str_size <- 1000;

class MyPdfToText
{
	const pdf_vline_max_top = 53;
	const pdf_line0_x = 39;
	const pdf_line0_y1 = 41;
	const pdf_line_y2 = 1172;

	const pdf_line4_x = 748;
	const pdf_line4_y1 = 41;

	auto pdf_text_lines = null;
	auto pdf_hv_lines = null;
	auto pdf_fonts = null;
	auto pdf_page_size = null
	auto pdf_min_max_xy = null;
	auto pdf_expected_v_lines = null;
	
	constructor()
	{
		pdf_text_lines = [];
		pdf_hv_lines = [];
		pdf_fonts = [];
		pdf_page_size = [788,1233];
		pdf_min_max_xy = [788, 0, 1233, 0];
		pdf_expected_v_lines = [
			214, 394, 573, //4 columns
			274, 513 //3 columns
			];
	}
	
	static function sortLinesV(a,b)
	{
		auto cmp = a[1] <=> b[1];
		if(cmp == 0) cmp = a[0] <=> b[0];
		return cmp;
	}

	static function sortLinesH(a,b)
	{
		auto cmp = a[0] <=> b[0];
		if(cmp == 0) cmp = a[1] <=> b[1];
		return cmp;
	}

	//need take into account utf-8
	static function isValidPrePosHyphen(c)
	{
		return  (c >= 'a' && c <= 'z') || 
				(c >= 'A' && c <= 'Z');
	}

	function findPdfBlocks(all_hv_lines)
	{

		auto math_abs = math.abs;
		auto function min_ab(a, b) {return a < b ? a : b;}
		auto function max_ab(a, b) {return a > b ? a : b;}

		//foreach(idx, line in hv_lines) print("findPdfBlocks", idx, line.join("\t"));
		auto v_lines = [];
		foreach(idx, line in all_hv_lines)
		{
			if(line[0] == line[2])
			{
				auto line_0 = line[0];
				if( pdf_expected_v_lines.find(line_0) >= 0 )
				{
					//reject some inner lines drawn upside down
					if(line[1] > line[3]) continue;
					v_lines.append(line);
				}
			}
		}
		
		auto normalizeMergeVLines()
		{
			//normalize v_lines duplicates one inside another
			auto tmp_vlines = [];
			for(auto i=0, len=v_lines.len(); i < len; ++i)
			{
				auto line = v_lines[i];
				auto done = false;
				
				for(auto i2=0; i2 < len; ++i2)
				{
					auto line2 = v_lines[i2];
					//both are in the same x
					if(line[0] == line2[0])
					{
						auto line2_y1 = line2[1];
						//is the start point inside this line ?
						if( (line2_y1 >= line[1]) && (line2_y1 <= line[3]) )
						{
							if( (line[1] == line2[1]) && (line[3] == line2[3]) ) continue;
							//print("Here", __LINE__, line.join("\t"), line2.join("\t"));
							tmp_vlines.append([line[0], min_ab(line[1], line2[1]), line[2], max_ab(line[3], line2[3]), line[4]]);
							break;
						}
					}
				}
			}
			//foreach(idx, line in tmp_vlines) print("tmp_vlines", idx, line.join("\t"));
			auto tmp_vlines_len = tmp_vlines.len();
			foreach(idx, line in v_lines)
			{
				auto done = false;
				for(auto i=0; i < tmp_vlines_len; ++i)
				{
					auto tmp_line = tmp_vlines[i];
					if(line[0] == tmp_line[0])
					{
						if( (line[1] >= tmp_line[1]) && (line[1] <= tmp_line[3]) )
						{
							done = true;
							break;
						}
					}
				}
				if(!done) tmp_vlines.append(line);
			}
			//foreach(idx, line in tmp_vlines) print("tmp_vlines", idx, line.join("\t"));
			v_lines = tmp_vlines;
		}
		normalizeMergeVLines();
		
		//normalize v_lines top/bottom
		for(auto i=0, len=v_lines.len(); i < len; ++i)
		{
			auto line = v_lines[i];
			if(line[1] < pdf_vline_max_top) line[1] = pdf_vline_max_top;
			
			auto l1y1 = line[1];
			auto l1y2 = line[3];
			for(auto i2=0; i2 < len; ++i2)
			{
				auto line2 = v_lines[i2];
				auto l2y1 = line2[1];
				auto l2y2 = line2[3];

				auto diff_y2 =  l1y2 - l2y2;
				if(math_abs(diff_y2) == 1)
				{
					//at bottom normalize bigger line_y2
					if(diff_y2 == 1) line2[3] = l1y2;
					else line[3] = l2y2;
				}

				auto diff_y1 =  l1y1 - l2y1;
				if(math_abs(diff_y1) == 1)
				{
					//print("Normalize top", diff_y1, l1y1, l2y1);
					//at top normalize smaller line_y1
					if(diff_y1 == 1) line[1] = l2y1;
					else line2[1] = l1y1;
				}
			}			
		}
		//foreach(idx, line in v_lines) print("v_lines0", idx, line.join("\t"));

		auto function iterateVlines(cb)
		{
			for(auto i=0, len=v_lines.len(); i < len; ++i)
			{
				auto line = v_lines[i];
				auto lx1 = line[0];
				auto ly1 = line[1];
				auto lx2 = line[2];
				auto ly2 = line[3];
				//if(lx1 == lx2) print("iterateHVlines", line.join("\t"));
				cb(i, lx1, ly1, lx2, ly2);
			}
		}
		
		auto min_re_y = pdf_line_y2;
		auto max_re_y = 0;
				
		auto line_sizes_normal_diff = 4;
		auto line_sizes_normalized = [];
		
		auto function findMaxMinY(idx, lx1, ly1, lx2, ly2)
		{
			if(min_re_y > ly1) min_re_y = ly1;
			if(max_re_y < ly2) max_re_y = ly2;
			
			auto done = false;
			auto nline = [lx1, ly1, ly2-ly1];
			foreach(lsz_idx, line_sz in line_sizes_normalized)
			{
				//print("findMaxMinY", line_sz[2], nline[2], line_sz.join("\t"), idx, lx1, ly1, lx2, ly2);
				auto sz_diff = math_abs(line_sz[2] - nline[2]);
				if( sz_diff <= line_sizes_normal_diff )
				{
					if( (math_abs(line_sz[1] - nline[1]) <= line_sizes_normal_diff) )
					{
						//print("findMaxMinY1", lsz_idx,  line_sz.join("\t"), nline.join("\t"), idx, lx1, ly1, lx2, ly2);
						line_sizes_normalized[lsz_idx] = [line_sz[0], min_ab(ly1, line_sz[1]), max_ab(line_sz[2], nline[2])];
						done = true;
						break;
					}
				}
			}
			if(!done) line_sizes_normalized.append(nline);
		}
		iterateVlines(findMaxMinY);
		//print("findMaxMinY", min_re_y, max_re_y);
		foreach(idx, line in v_lines) print("v_lines", idx, line.join("\t"));
		//foreach(idx, line in line_sizes_normalized) print("line_sizes_normalized", idx, line.join("\t"));

		auto function normalizeLines(idx, lx1, ly1, lx2, ly2)
		{
			//print("normalizeLines", idx, lx1, ly1, lx2, ly2);
			auto nline = [lx1, ly1, ly2-ly1];
			foreach(line_sz in line_sizes_normalized)
			{
				//print("normalizeLines1", line_sz.join("\t"));
				auto sz_diff = math_abs(line_sz[2] - nline[2]);
				//print("normalizeLines1", sz_diff);
				if( sz_diff && (sz_diff <= line_sizes_normal_diff) )
				{
					//print("normalizeLines2", line_sz.join("\t"));
					sz_diff = math_abs(line_sz[1] - nline[1]);
					if( sz_diff <= line_sizes_normal_diff )
					{
						//print("normalizeLines3", line_sz.join("\t"));
						v_lines[idx] = [nline[0], line_sz[1], nline[0], line_sz[1]+line_sz[2]];
						break;
					}
				}
			}
		}
		iterateVlines(normalizeLines);
		
		v_lines.sort(sortLinesH);
		
		foreach(idx, line in v_lines)
		{
			if(line[3] != pdf_line_y2) //only check lines that not touch page bottom
			{
				//print("hack to round bottom line", line.join("\t"));
				//hack to round bottom line
				auto new_y2 = line[3] + 4; //4 = half line rounding
				v_lines[idx][3] = (new_y2 > pdf_line_y2) ? pdf_line_y2 : new_y2;
			}
		}
		//foreach(idx, line in v_lines) print("v_lines_h_sorted", idx, line.join("\t"));
		
		auto function getLineNeighbor(px, py, py2, direction)
		{
			auto result, isDirLeft = direction == -1;
			//print("getLineNeighbor0", px, py, py2, direction);
			foreach(idx, line in v_lines)
			{
				if( (line[0] == px) && (py2 == line[3]) )
				{
					//print("getLineNeighbor0", idx, line.join("\t"));
					if(isDirLeft)
					{
						auto prev_idx = idx;
						while(--prev_idx >= 0)
						{
							auto prev_line = v_lines[prev_idx];
							if(prev_line[0] == px)
							{
								continue;
							}
							//print("getLineNeighborLeft", prev_line.join("\t"), px, py, py2);
							if((px > prev_line[0]) && (py >= prev_line[1])
								&& (py < prev_line[3]) && (prev_line[3] >= py2))
							//if((prev_line[1] == py) && (prev_line[3] >= py2))
							{
								result = [prev_line[0]+1, prev_line[1], prev_line[3]];
								break;
							}
							//break;
						}
					}
					else
					{
						auto next_idx = idx;
						while(++next_idx < v_lines.len())
						{
							auto next_line = v_lines[next_idx];
							if(next_line[0] == px)
							{
								continue;
							}
							//print("Check neighborgh", px, py, next_line.join("\t"));
							if((px < next_line[0]) && (py >= next_line[1])
								&& (py < next_line[3]) && (next_line[3] >= py2))
							//if((next_line[1] == py) && (next_line[3] >= py2))
							{
								result = [next_line[0]-1, next_line[1], next_line[3]];
								break;
							}
							//break;
						}
					}
				}
				if(result != null) break;
			}
			if(result == null) result = [(isDirLeft ? pdf_line0_x : pdf_line4_x), pdf_line0_y1, pdf_line_y2];
			//print("getLineNeighbor", px, py, py2, direction, result.join("\t"));
			return result;
		}

		auto re_points = [
				[pdf_line0_x,pdf_line0_y1], [pdf_line0_x,pdf_line_y2],
				[pdf_line4_x, pdf_line0_y1], [pdf_line4_x, pdf_line_y2]
			];
		auto near_bottom_y =  pdf_line_y2 -8;
		auto near_top_y =  min_re_y-1;
		
		auto function fill_re_points(idx, lx1, ly1, lx2, ly2)
		{		
			auto function addRePoint(px, py)
			{
				//print("addRePoint1", re_points.len(), px, py);
				if(py >= near_bottom_y) py = pdf_line_y2;
				/*
				if(py == near_top_y)
				{
					if( (px > pdf_line0_x) && (px < pdf_line4_x) ) py = near_top_y+1;
				}
				*/
				//print("addRePoint2", re_points.len(), px, py);
				re_points.append([px, py]);
			}
			
			auto function reflectPoint()
			{
				auto left_line = getLineNeighbor(lx1, ly1, ly2, -1);
				auto left_x = left_line[0];
				if(left_line[1] < ly1) addRePoint(left_x, ly1-1);
				addRePoint(left_x, ly1);

				addRePoint(left_x, ly2);
				if(left_line[2] > ly2) addRePoint(left_x, ly2+1);
				
				auto rigth_line = getLineNeighbor(lx1, ly1, ly2, 1);
				auto rigth_x = rigth_line[0];
				if(rigth_line[1] < ly1)addRePoint(rigth_x, ly1-1);
				addRePoint(rigth_x, ly1);

				addRePoint(rigth_x, ly2);
				if(rigth_line[2] > ly2)addRePoint(rigth_x, ly2+1);

				//print("reflectPoint", left_x, lx1, rigth_x, ly1);
			}
			
			//print("Adding new points", lx1, ly1, lx2, ly2);
			addRePoint(lx1-1, ly1);
			addRePoint(lx2-1, ly2);
			addRePoint(lx1+1, ly1);
			addRePoint(lx2+1, ly2);
			reflectPoint();
		}
		
		iterateVlines(fill_re_points);

		//remove duplicates
		re_points.sort(sortLinesH);
		//foreach(idx, pt in re_points) print("all re points", idx, pt[0], pt[1]);
		auto last_re_point_x;
		auto last_re_point_y;
		auto unique_re_points = [];
		foreach(idx, pt in re_points)
		{
			if( (last_re_point_x == pt[0]) && (last_re_point_y == pt[1]) ) continue;
			unique_re_points.append(pt);
			last_re_point_x = pt[0];
			last_re_point_y = pt[1];
		}
		re_points = unique_re_points;
		//foreach(idx, pt in re_points) print("re points", idx, pt[0], pt[1]);
		
		auto mix_points = [];
		for(auto i=0, len=re_points.len(); i < len; i+=2)
		{
			auto rep1 = re_points[i];
			auto rep2 = re_points[i+1];
			mix_points.append([rep1[0], rep1[1], rep2[1]]);
		}
		mix_points.sort(sortLinesV);
		//foreach(idx, pt in mix_points) print("mix_points", idx, pt.join("\t"));
		
		auto re_blocks = [];
		for(auto i=0, len=mix_points.len(); i < len; i+=2)
		{
			auto rep1 = mix_points[i];
			auto rep2 = mix_points[i+1];
			re_blocks.append([rep1[0], rep1[1], rep2[0], rep1[2]]);
		}
		//foreach(idx, blk in re_blocks) print("Blocks list", idx, blk.join("\t"));
		
		auto re_blocks_sorted = [];
		
		auto function getNextBlock()
		{
			if(re_blocks_sorted.len())
			{
				auto prev_blk = re_blocks_sorted.top();
				auto next_blk = -1;
				foreach(idx, blk in re_blocks)
				{
					if(blk == null) continue;
					if(next_blk < 0) next_blk = idx;
					if( (blk[1] == prev_blk[1]) && (blk[3] == prev_blk[3]) )
					{
						next_blk = idx;
						break;
					}
					if( (prev_blk[0] >= blk[0]) && (blk[1] == (prev_blk[3]+1)) )
					{
						next_blk = idx;
						break;
					}
				}
				if(next_blk >= 0)
				{
					re_blocks_sorted.append(re_blocks[next_blk]);
					re_blocks[next_blk] = null;
					return true;
				}
			}
			else if(re_blocks.len())
			{
				re_blocks_sorted.append(re_blocks[0]);
				re_blocks[0] = null;
				return true;
			}
			return false;
		}

		while(getNextBlock()){} //move one by one in reading order
		
		//foreach(idx, blk in re_blocks_sorted) print("Blocks sorted list", idx, blk.join("\t"));
		
		return re_blocks_sorted;
	}
	
	function getTextLines(text)
	{
		auto self = this;
		text.gmatch(
			//":(%d+):(%d+):(%d+):(%d+):(%d+):([^\n]+)\n",
			//function(cx, cy, cl, cf, cid, line)
			":(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):([^\n]+)\n",
			function(cx, cy, cx2, cf, cid, line)
			{
				cx = cx.tointeger();
				cx2 = cx2.tointeger();
				cy = cy.tointeger();
				if(cx < 0)
				{
					//print(cx, cy);
					switch(cx)
					{
						//fonts
						case -1:
							self.pdf_fonts.append([cid.tointeger(), line]);
						break;
						//page size
						case -2:
							self.pdf_page_size = [cx2, cf.tointeger()];
						break;
						//lines
						case -4:
						{
							auto lx1 = cy;
							auto lx2 = cf.tointeger();
							auto ly1 = cx2;
							auto ly2 = cid.tointeger();
							
							self.pdf_hv_lines.append([lx1, ly1, lx2, ly2, 1]);
						}
						break;
					}
					return true;
				}

				auto pdf_min_max_xy = self.pdf_min_max_xy;

				if(cx < pdf_min_max_xy[0]) pdf_min_max_xy[0] = cx;
				if(cx2 > pdf_min_max_xy[1]) pdf_min_max_xy[1] = cx2;

				if(cy < pdf_min_max_xy[2]) pdf_min_max_xy[2] = cy;
				else if(cy > pdf_min_max_xy[3]) pdf_min_max_xy[3] = cy;
				
				self.pdf_text_lines.append([cx, cy, cx2, cf, line]);
				return true;
			}
		);
	}
	
	function getText(text_fn)
	{
		auto text = readfile(text_fn);
		getTextLines(text);
		auto pdf_blocks = findPdfBlocks(pdf_hv_lines);

		auto last_block = null;
		auto line_heigth = 10;
		auto result = blob(0, text.len());

		foreach(blk in pdf_blocks)
		{
			auto x1 = blk[0];
			auto y1 = blk[1];
			auto x2 = blk[2];
			auto y2 = blk[3];
			
			auto block_lines = [];
			
			//print("pdf_block", blk.join("\t"));
			foreach(line in pdf_text_lines)
			{
				if( (line[0] >= blk[0]) && (line[0] <= blk[2]) )
				{
					if( (line[1] >= blk[1]) )
					{
						auto bottom_y_diff =  line[1] - blk[3];
						//give some tolerance for the bottom line
						//if( bottom_y_diff <= 4 ) //4 = half line
						if( bottom_y_diff <= 0 )
						{
							//print("block append", line.join("\t"));
							block_lines.append(line);
						}
					}
				}
			}
			block_lines.sort(sortLinesV);

			//merge lines segments
			auto last_line_idx = null;
			auto last_line_x2 = 0;
			foreach(idx, line in block_lines)
			{
				if(last_line_idx != null)
				{
					auto last_line = block_lines[last_line_idx];
					if(last_line)
					{
						if(last_line[1] == line[1])
						{
							auto space_str = " ";
							auto spaces = line[0] - last_line_x2; //last_line[2];
							if(spaces > 0)
							{
								//auto space_width = (line[2]-line[0]) / line[4].len();
								//if(space_width && (spaces > space_width)) spaces /= space_width;
								if(spaces > 2) spaces /= 2;
								else spaces = 1;
								space_str = space_str.rep(spaces);
							}
							block_lines[last_line_idx][4] += space_str + line[4];
							block_lines[idx] = null;
							last_line_x2 = line[2];
							continue;
						}
						auto last_text_line = last_line[4];
						auto last_text_line_len = last_text_line.len();
						if((last_text_line_len > 1) && (last_text_line[last_text_line_len-1] == '-'))
						{
							if(isValidPrePosHyphen(last_text_line[last_text_line_len-2]))
							{
								auto line_len = line.len();
								if(line_len  > 1)
								{
									if(isValidPrePosHyphen(line[4][0]))
									{
										block_lines[last_line_idx][4] = block_lines[last_line_idx][4].slice(0, -1) + line[4];
										block_lines[idx] = null;
									}
								}
							}
						}
					}
					last_line_x2 = line[2];
				}
				last_line_idx = idx;
			}

			if(last_block)
			{
				if(last_block[0] == blk[0])
				{
					auto vsize = blk[1] - last_block[1];
					if(vsize > line_heigth) result.write("\n");
				}
			}
			auto last_line = null;
			foreach(line_idx, line in block_lines)
			{
				if(!line)
				{
					last_line = null; //prevent white lines after hyphen removal
					continue;
				}
				if(line_idx == 0)
				{
					//need vertical space at the begin of this block ?
					auto new_lines = (line[1] - blk[1])/line_heigth;
					if(new_lines)
					{
						auto new_line_str = "\n".rep(new_lines);
						result.write(new_line_str);
					}			
				}
				if(last_line)
				{
					auto vsize = line[1] - last_line[1];
					if(vsize > line_heigth) result.write("\n");
				}
				auto spaces = (line[0] - blk[0]) - 8;
				if(spaces > 0)
				{
					//auto space_width = (line[2]-line[0]) / line[4].len();
					//if(space_width && (spaces > space_width)) spaces /= space_width;
					if(spaces > 2) spaces /= 2;
					else spaces = 1;
					auto space_str = " ".rep(spaces);
					result.write(space_str);
				}
				result.write(line[4]);
				result.write("\n");
				last_line = line;
			}
			last_block = blk;
		}
		return result;
	}
}


auto base_folder = "../tmp3/";

//auto text_fn = "do-2010-02-04-0043.txt";
//auto text_fn = "do-2010-02-20-0029.txt";
//auto text_fn = "do-2010-02-27-0059.txt";
//auto text_fn = "do-2010-03-02-0042.txt";
//auto text_fn = "do-2010-03-04-0076.txt";
//auto text_fn = "do-2010-03-16-0031.txt";
//auto text_fn = "do-2010-03-24-0032.txt";
//auto text_fn = "do-2010-03-27-0076.txt";
///auto text_fn = "do-2010-03-31-0118.txt";
//auto text_fn = "do-2010-04-01-0100.txt";
//auto text_fn = "do-2010-04-07-0173.txt";
//auto text_fn = "do-2010-04-23-0087.txt";
//auto text_fn = "do-2010-05-29-0212.txt";
//auto text_fn = "do-2010-06-19-0097.txt";
//auto text_fn = "do-2010-07-01-0016.txt";
//auto text_fn = "do-2010-07-13-0078.txt";
//auto text_fn = "do-2010-07-27-0066.txt";
//auto text_fn = "do-2010-08-07-0082.txt";
///auto text_fn = "do-2010-09-17-0067.txt";
//auto text_fn = "do-2010-10-06-0089.txt";
//auto text_fn = "do-2010-10-07-0084.txt";
//auto text_fn = "do-2010-10-16-0064.txt";
//auto text_fn = "do-2010-10-29-0037.txt";
//auto text_fn = "do-2010-11-10-0127.txt";
//auto text_fn = "do-2010-11-12-0033.txt";
//auto text_fn = "do-2010-12-07-0082.txt";
//auto text_fn = "do-2010-12-15-0252.txt";
//auto text_fn = "do-2010-12-18-0131.txt";
//auto text_fn = "do-2011-01-19-0018.txt";
//auto text_fn = "do-2011-01-29-0013.txt";
//auto text_fn = "do-2012-06-13-0343.txt";
//auto text_fn = "do-2016-05-24-0070.txt";
auto text_fn = "do-2010-09-17-0067.txt";
//auto text_fn = "do-2012-06-13-0343.txt";
//auto text_fn = "do-2012-06-21-0231.txt";
//auto text_fn = "do-2013-10-10-0087.txt";
//auto text_fn = "do-2016-05-24-0070.txt";
//auto text_fn = "do-2013-02-06-0075.txt";

auto mypdftotext = new MyPdfToText();
auto text = mypdftotext.getText(base_folder + text_fn);
print(text.tostring());